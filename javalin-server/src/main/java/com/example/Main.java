package com.example;

import io.javalin.Javalin;
import io.javalin.http.Context;
import io.javalin.http.sse.SseClient;
import io.javalin.json.JavalinJackson;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.*;
import java.util.regex.Pattern;

public class Main {

    // ===== Job model =====
    public static class Job {
        public String id;
        public String type;
        public String status;
        public Instant startedAt;
        public Instant finishedAt;
        public List<String> output = new ArrayList<>();
    }

    // ===== Globals =====
    private static final Map<String, Job> jobs = new ConcurrentHashMap<>();
    private static final ExecutorService executor = Executors.newSingleThreadExecutor();
    private static final Pattern DOMAIN_PATTERN =
            Pattern.compile("^[a-zA-Z0-9_-]+(\\.[a-zA-Z0-9_-]+)+$");

    public static void main(String[] args) {

        // ===== Configure Jackson to handle Instant =====
        ObjectMapper objectMapper = new ObjectMapper();
        objectMapper.registerModule(new JavaTimeModule());

        Javalin app = Javalin.create(config -> {
            config.jsonMapper(new JavalinJackson(objectMapper));
            // Enable CORS for all origins
            config.plugins.enableCors(cors -> {
                cors.add(corsConfig -> {
                    corsConfig.anyHost();
                });
            });
        }).start(7070);

        // ---------------- HEALTH ----------------
        app.get("/health", ctx ->
                ctx.json(Map.of("status", "UP"))
        );

        // ---------------- ANSIBLE STATUS ----------------
        app.get("/ansible/status", ctx ->
                ctx.json(Map.of(
                        "running", jobs.values().stream().anyMatch(j -> "RUNNING".equals(j.status))
                ))
        );

        // ---------------- RESET LDAP ----------------
        app.post("/ldap/reset", ctx -> {
            createJob(ctx, "reset", List.of(
                    "ansible-playbook",
                    "-i", "inventory.py",
                    "reset_test.yaml",
                    "-b"
            ));
        });

        // ---------------- INSTALL LDAP ----------------
        app.post("/ldap/install", ctx -> {
            Map<String, Object> body = ctx.bodyAsClass(Map.class);
            String domain = body.get("domain").toString();
            String password = body.get("adminPassword").toString();

            validateDomain(domain);
            String suffix = domainToSuffix(domain);

            createJob(ctx, "install", List.of(
                    "ansible-playbook",
                    "-i", "inventory.py",
                    "test_install.yml",
                    "-b",
                    "-e",
                    "ldap_suffix=" + suffix + " ldap_admin_password=" + password
            ));
        });

        // ---------------- ADD DOMAIN ----------------
        app.post("/ldap/domain/add", ctx -> {
            Map<String, Object> body = ctx.bodyAsClass(Map.class);
            String domain = body.get("domain").toString();
            String password = body.get("adminPassword").toString();

            validateDomain(domain);

            createJob(ctx, "add-domain", List.of(
                    "ansible-playbook",
                    "-i", "inventory.py",
                    "add-domain.yml",
                    "-e",
                    "new_domain=" + domain +
                            " new_domain_admin_password=" + password
            ));
        });

        // ---------------- JOB LIST (metadata only, no logs) ----------------
        app.get("/jobs", ctx -> {
            List<Map<String, Object>> metadata = new ArrayList<>();
            for (Job job : jobs.values()) {
                Map<String, Object> meta = new HashMap<>();
                meta.put("id", job.id);
                meta.put("type", job.type);
                meta.put("status", job.status);
                meta.put("startedAt", job.startedAt);
                meta.put("finishedAt", job.finishedAt);
                metadata.add(meta);
            }
            ctx.json(metadata);
        });

        // ---------------- JOB LOGS ----------------
        app.get("/jobs/{id}/output", ctx -> {
            Job job = jobs.get(ctx.pathParam("id"));
            if (job == null) {
                ctx.status(404).json(Map.of("error", "Job not found"));
                return;
            }
            ctx.json(job.output);
        });


        // ---------------- LIVE JOB LOG STREAM (Javalin 5 SSE) ----------------
        // ---------------- LIVE JOB LOG STREAM (Javalin 5 SSE) ----------------
        app.sse("/jobs/{id}/stream", client -> {
            String jobId = client.ctx().pathParam("id");
            Job job = jobs.get(jobId);

            if (job == null) {
                client.ctx().status(404).result("Job not found");
                client.close();
                return;
            }

            System.out.println("SSE client connected for job " + jobId); // DEBUG

            // Start a scheduler to check logs
            final int[] lastIndex = {0};
            ScheduledExecutorService scheduler = Executors.newSingleThreadScheduledExecutor();

            scheduler.scheduleAtFixedRate(() -> {
                synchronized (job.output) {
                    while (lastIndex[0] < job.output.size()) {
                        String line = job.output.get(lastIndex[0]);
                        client.sendEvent("log", line); // flush each line
                        lastIndex[0]++;
                    }

                    if ("SUCCESS".equals(job.status) || "FAILED".equals(job.status)) {
                        client.sendEvent("status", job.status);
                        client.close();
                        scheduler.shutdown();
                    }
                }
            }, 0, 100, TimeUnit.MILLISECONDS);


            // If client disconnects
            client.onClose(() -> {
                System.out.println("SSE client disconnected for job " + jobId);
                scheduler.shutdown();
            });
        });



    }

    // ===== Helper methods =====

    private static void createJob(Context ctx, String type, List<String> command) {
        String jobId = type + "-" + System.currentTimeMillis();

        Job job = new Job();
        job.id = jobId;
        job.type = type;
        job.status = "RUNNING";
        job.startedAt = Instant.now();

        jobs.put(jobId, job);

        executor.submit(() -> runCommand(job, command));

        ctx.json(Map.of(
                "jobId", jobId,
                "status", "STARTED"
        ));
    }

    private static void runCommand(Job job, List<String> command) {
        try {
            ProcessBuilder pb = new ProcessBuilder(command);
            pb.directory(new java.io.File(System.getProperty("user.home") + "/ldap-cluster-new"));
            pb.redirectErrorStream(true);

            Process process = pb.start();

            try (BufferedReader reader =
                         new BufferedReader(new InputStreamReader(process.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    job.output.add(line);
                }
            }

            int exitCode = process.waitFor();
            job.status = exitCode == 0 ? "SUCCESS" : "FAILED";

        } catch (Exception e) {
            job.output.add(e.getMessage());
            job.status = "FAILED";
        } finally {
            job.finishedAt = Instant.now();
        }
    }

    private static void streamJobLogs(Job job, SseClient client) {
        final int[] lastIndex = {0};
        ScheduledExecutorService scheduler = Executors.newSingleThreadScheduledExecutor();

        scheduler.scheduleAtFixedRate(() -> {
            synchronized (job.output) {
                while (lastIndex[0] < job.output.size()) {
                    client.sendEvent("log", job.output.get(lastIndex[0]));
                    lastIndex[0]++;
                }
                if ("SUCCESS".equals(job.status) || "FAILED".equals(job.status)) {
                    client.sendEvent("status", job.status);
                    client.close();
                    scheduler.shutdown();
                }
            }
        }, 0, 500, TimeUnit.MILLISECONDS);

        client.onClose(() -> scheduler.shutdown());
    }

    private static void validateDomain(String domain) {
        if (!DOMAIN_PATTERN.matcher(domain).matches()) {
            throw new IllegalArgumentException("Invalid domain format");
        }
    }

    private static String domainToSuffix(String domain) {
        StringBuilder sb = new StringBuilder();
        for (String part : domain.split("\\.")) {
            if (sb.length() > 0) sb.append(",");
            sb.append("dc=").append(part);
        }
        return sb.toString();
    }
}
