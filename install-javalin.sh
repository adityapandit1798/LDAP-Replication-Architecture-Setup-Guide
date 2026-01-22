#!/bin/bash

# Exit immediately if any command fails
set -e

echo "🚀 Starting Javalin setup..."

# Check if Java is installed
if ! command -v java &> /dev/null; then
    echo "Java not found, installing..."
    sudo apt update
    sudo apt install -y openjdk-17-jdk
else
    echo "Java is already installed"
fi

# Check if Maven is installed
if ! command -v mvn &> /dev/null; then
    echo "Maven not found, installing..."
    sudo apt install -y maven
else
    echo "Maven is already installed"
fi

# Set up project directory
PROJECT_DIR=~/javalin-server
mkdir -p "$PROJECT_DIR/src/main/java/com/example"
cd "$PROJECT_DIR"

# Create basic pom.xml with Javalin dependency
cat > pom.xml <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.example</groupId>
    <artifactId>javalin-server</artifactId>
    <version>1.0-SNAPSHOT</version>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>

    <dependencies>
        <dependency>
            <groupId>io.javalin</groupId>
            <artifactId>javalin</artifactId>
            <version>5.6.2</version>
        </dependency>
    </dependencies>
</project>
EOF

# Create the new simplified Main.java class
cat > "$PROJECT_DIR/src/main/java/com/example/Main.java" <<'EOF'
package com.example;

import io.javalin.Javalin;

public class Main {
    public static void main(String[] args) {
        // Create and start the Javalin server on port 7070
        Javalin app = Javalin.create().start(7070);

        // Define a basic GET route
        app.get("/", ctx -> {
            ctx.result("Hello, Javalin is up and running! 🚀");
        });

        // Define another GET route to test server
        app.get("/test", ctx -> {
            ctx.result("This is a test route.");
        });

        // Add more routes as needed
    }
}
EOF

# Build the project
mvn clean package

echo "✅ Setup complete. To run the Javalin server:"
echo "cd $PROJECT_DIR && mvn exec:java -Dexec.mainClass=com.example.Main"
