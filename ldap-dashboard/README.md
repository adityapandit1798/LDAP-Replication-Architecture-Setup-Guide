# LDAP Dashboard

A modern web dashboard for managing LDAP clusters via REST API.

## Features

- Real-time monitoring of LDAP cluster status
- Job management and log viewing
- Domain installation and management
- Remote API access with configurable endpoints
- Responsive design with modern UI

## Setup

### Backend (Java Server)

1. Start the Javalin server:
```bash
cd /home/ansible-ldap/ldap-cluster-new/javalin-server
./mvnw compile exec:java
```
The server will start on port 7070 with CORS enabled.

### Frontend (Dashboard)

1. Open `index.html` in a web browser
2. Click "Configure" in the header to set the API URL
3. Enter the remote server URL (e.g., `http://192.168.1.100:7070`)

## API Endpoints

The dashboard integrates with the following endpoints:

### Monitoring
- `GET /health` - Server health check
- `GET /ansible/status` - Check if jobs are running
- `GET /jobs` - List all jobs (metadata only)

### Management
- `POST /ldap/reset` - Reset LDAP cluster
- `POST /ldap/install` - Install LDAP for a domain
- `POST /ldap/domain/add` - Add new domain

### Logs
- `GET /jobs/{id}/output` - Get job logs
- `GET /jobs/{id}/stream` - Real-time log streaming (SSE)

## Remote Access

### From Local Machine
1. Ensure the backend server is accessible
2. Configure firewall to allow port 7070
3. Use the dashboard's "Configure" button to set the remote API URL

### Network Requirements
- Port 7070 must be open on the server
- CORS is enabled on the backend
- No authentication required (add as needed for production)

### Example Configuration
```
API URL: http://remote-server-ip:7070
```

## Usage

1. **Monitor Status**: View real-time stats in the dashboard
2. **Install LDAP**: Click "Install LDAP" and provide domain/password
3. **Add Domain**: Click "Add Domain" for additional domains
4. **Reset Cluster**: Click "Reset LDAP" (with confirmation)
5. **View Logs**: Click "View Job Logs" to see detailed output
6. **Test Connection**: Verify API connectivity

## Security Notes

- Current setup has no authentication
- CORS is enabled for all origins (restrict in production)
- Consider adding HTTPS for production use
- Implement authentication/authorization as needed

## Troubleshooting

### CORS Errors
Ensure the backend has CORS enabled (included in the Java server).

### Network Errors
- Check if port 7070 is open on the server
- Verify the API URL is correct
- Ensure the backend server is running

### Connection Issues
- Use browser developer tools to check network requests
- Verify the server IP and port are accessible
- Check firewall rules on both client and server
