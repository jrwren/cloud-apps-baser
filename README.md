# cloud-apps-baser is more baser than base. it is based.

Don't use this. It exists for bespoke reasons.

### Features
 * stdout and stderr logs to filebeat
 * haproxy for TLS termination
 * check-frontend.sh

### To use it

1. Create a /run.sh and add it to a container based on this container.
1. On startup, /run.sh is executed and backgrounded. It is expected that /run.sh
creates a /run/app.pid.
1. The application invoked in /run.sh should create its HTTP listener port on
port $NOMAD_PORT_http
