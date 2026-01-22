// API configuration - set to remote server IP
const API_BASE_URL = 'http://192.168.192.159:7070';

// Show current API URL in console for debugging
console.log('Current API URL:', API_BASE_URL);

// DOM elements
const activeUsersEl = document.getElementById('active-users');
const domainCountEl = document.getElementById('domain-count');
const serverStatusEl = document.getElementById('server-status');
const lastSyncEl = document.getElementById('last-sync');
const logOutputEl = document.getElementById('log-output');
const loadingOverlayEl = document.getElementById('loading-overlay');

// Initialize dashboard on page load
document.addEventListener('DOMContentLoaded', function() {
    addLogEntry(`Dashboard loaded. Connected to: ${API_BASE_URL}`, 'success');
    refreshData();
});

// Show/hide loading overlay
function toggleLoading(show) {
    if (show) {
        loadingOverlayEl.classList.remove('hidden');
    } else {
        loadingOverlayEl.classList.add('hidden');
    }
}

// Add entry to activity log
function addLogEntry(message, type = 'info') {
    const timestamp = new Date().toLocaleString();
    const logEntry = document.createElement('div');
    logEntry.className = `log-entry ${type}`;
    logEntry.textContent = `[${timestamp}] ${message}`;
    
    logOutputEl.appendChild(logEntry);
    logOutputEl.scrollTop = logOutputEl.scrollHeight;
}

// Make API request
async function makeApiRequest(endpoint, options = {}) {
    try {
        const url = `${API_BASE_URL}${endpoint}`;
        const response = await fetch(url, {
            headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                ...options.headers
            },
            mode: 'cors',
            ...options
        });
        
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }
        
        return await response.json();
    } catch (error) {
        let errorMessage = `API Error: ${error.message}`;
        
        if (error.message.includes('Failed to fetch') || error.message.includes('NetworkError')) {
            errorMessage = `Network Error: Cannot reach ${API_BASE_URL}. Check if the server is running and accessible.`;
        } else if (error.message.includes('CORS')) {
            errorMessage = `CORS Error: Server at ${API_BASE_URL} does not allow cross-origin requests. Configure CORS on the backend.`;
        }
        
        addLogEntry(errorMessage, 'error');
        throw error;
    }
}

// Refresh dashboard data
async function refreshData() {
    toggleLoading(true);
    addLogEntry('Refreshing dashboard data...', 'info');
    
    try {
        await Promise.all([
            fetchHealthStatus(),
            fetchAnsibleStatus(),
            fetchJobsList()
        ]);
        
        addLogEntry('Dashboard data refreshed successfully', 'success');
    } catch (error) {
        addLogEntry('Failed to refresh some data', 'error');
    } finally {
        toggleLoading(false);
    }
}

// Fetch health status
async function fetchHealthStatus() {
    try {
        const data = await makeApiRequest('/health');
        serverStatusEl.innerHTML = `<span style="color: ${data.status === 'UP' ? '#48bb78' : '#e53e3e'};">${data.status}</span>`;
        addLogEntry(`Health status: ${data.status}`, 'success');
    } catch (error) {
        serverStatusEl.innerHTML = '<span style="color: #e53e3e;">Error</span>';
    }
}

// Fetch Ansible status
async function fetchAnsibleStatus() {
    try {
        const data = await makeApiRequest('/ansible/status');
        const status = data.running ? 'Running' : 'Idle';
        activeUsersEl.innerHTML = `<span style="color: ${data.running ? '#48bb78' : '#666'};">${status}</span>`;
        addLogEntry(`Ansible status: ${status}`, 'success');
    } catch (error) {
        activeUsersEl.textContent = 'Error';
    }
}

// Fetch jobs list
async function fetchJobsList() {
    try {
        const jobs = await makeApiRequest('/jobs');
        const runningJobs = jobs.filter(job => job.status === 'RUNNING').length;
        const completedJobs = jobs.filter(job => job.status === 'SUCCESS').length;
        
        domainCountEl.textContent = runningJobs;
        lastSyncEl.textContent = `${completedJobs} completed`;
        
        addLogEntry(`Jobs: ${runningJobs} running, ${completedJobs} completed`, 'success');
    } catch (error) {
        domainCountEl.textContent = 'Error';
        lastSyncEl.textContent = 'Error';
    }
}

// Test API connection
async function testConnection() {
    toggleLoading(true);
    addLogEntry('Testing API connection...', 'info');
    
    try {
        const data = await makeApiRequest('/health');
        addLogEntry(`API connection successful - Status: ${data.status}`, 'success');
    } catch (error) {
        addLogEntry('API connection failed', 'error');
    } finally {
        toggleLoading(false);
    }
}

// Show detailed job logs
async function showLogs() {
    addLogEntry('Fetching job logs...', 'info');
    
    try {
        const jobs = await makeApiRequest('/jobs');
        if (jobs.length === 0) {
            addLogEntry('No jobs found', 'info');
            return;
        }
        
        // Show logs for the most recent job
        const latestJob = jobs[0];
        const jobLogs = await makeApiRequest(`/jobs/${latestJob.id}/output`);
        
        addLogEntry(`=== Logs for job ${latestJob.id} (${latestJob.status}) ===`, 'info');
        jobLogs.forEach(line => {
            if (line.trim()) {
                addLogEntry(line, 'info');
            }
        });
        
        document.querySelector('.logs-section').scrollIntoView({ behavior: 'smooth' });
    } catch (error) {
        addLogEntry('Failed to fetch job logs', 'error');
    }
}

// Reset LDAP
async function resetLDAP() {
    if (!confirm('Are you sure you want to reset LDAP? This will stop all services and clear data.')) {
        return;
    }
    
    toggleLoading(true);
    addLogEntry('Starting LDAP reset...', 'info');
    
    try {
        const data = await makeApiRequest('/ldap/reset', { method: 'POST' });
        addLogEntry(`LDAP reset started - Job ID: ${data.jobId}`, 'success');
        
        // Refresh jobs to show the new job
        setTimeout(() => fetchJobsList(), 1000);
    } catch (error) {
        addLogEntry('LDAP reset failed', 'error');
    } finally {
        toggleLoading(false);
    }
}

// Install LDAP
async function installLDAP() {
    const domain = prompt('Enter domain name (e.g., example.com):');
    const adminPassword = prompt('Enter admin password:');
    
    if (!domain || !adminPassword) {
        addLogEntry('Domain and password are required', 'error');
        return;
    }
    
    toggleLoading(true);
    addLogEntry(`Installing LDAP for domain: ${domain}`, 'info');
    
    try {
        const data = await makeApiRequest('/ldap/install', {
            method: 'POST',
            body: JSON.stringify({ domain, adminPassword })
        });
        addLogEntry(`LDAP installation started - Job ID: ${data.jobId}`, 'success');
        
        // Refresh jobs to show the new job
        setTimeout(() => fetchJobsList(), 1000);
    } catch (error) {
        addLogEntry('LDAP installation failed', 'error');
    } finally {
        toggleLoading(false);
    }
}

// Add Domain
async function addDomain() {
    const domain = prompt('Enter new domain name (e.g., newdomain.com):');
    const adminPassword = prompt('Enter admin password:');
    
    if (!domain || !adminPassword) {
        addLogEntry('Domain and password are required', 'error');
        return;
    }
    
    toggleLoading(true);
    addLogEntry(`Adding domain: ${domain}`, 'info');
    
    try {
        const data = await makeApiRequest('/ldap/domain/add', {
            method: 'POST',
            body: JSON.stringify({ domain, adminPassword })
        });
        addLogEntry(`Domain addition started - Job ID: ${data.jobId}`, 'success');
        
        // Refresh jobs to show the new job
        setTimeout(() => fetchJobsList(), 1000);
    } catch (error) {
        addLogEntry('Domain addition failed', 'error');
    } finally {
        toggleLoading(false);
    }
}

// Auto-refresh every 30 seconds
setInterval(() => {
    refreshData();
}, 30000);

// Handle keyboard shortcuts
document.addEventListener('keydown', function(event) {
    if (event.ctrlKey || event.metaKey) {
        switch (event.key) {
            case 'r':
                event.preventDefault();
                refreshData();
                break;
            case 'l':
                event.preventDefault();
                showLogs();
                break;
        }
    }
});
