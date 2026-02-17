# Bash Watchdog Monitor

## Overview

A cron-based service monitoring system written in pure Bash.

It monitors multiple endpoints, tracks state transitions using threshold-based failure detection, logs status changes, and sends email alerts.

## Features

- Cron-based service monitoring
- Supports multiple endpoints
- Threshold-based failure detection
- Logs state transitions
- Email alerting via msmtp
- Prevents duplicate execution using flock


## Architecture

watchdog.sh – Main monitoring script
services.conf – Service configuration file
state.db – Stores previous state
monitor.log – Transition log
error.log – Execution errors
cron – Scheduler
msmtp – Email delivery mechanism

State File Format
```text
NAME STATUS FAILURE_COUNT
```


Example:

Google-HTTPS UP 0
Local-HTTP DOWN 3

Log Format
```text
DATE NAME HOST PORT MODE THRESHOLD PATH STATUS
```


Example:
```text
Sun Feb 15 12:32:13 PM IST 2026 Local-HTTP localhost 8000 http 3 / DOWN
Sun Feb 15 12:32:43 PM IST 2026 Local-HTTP localhost 8000 http 3 / UP
```

Logs are written only on state transitions.

## Technical Flow

CRON triggers the script
        ↓
Lock mechanism prevents overlap
        ↓
Services loaded from services.conf
        ↓
Each service is checked
        ↓
If threshold-based transition occurs:
    → Log is written
    → state.db is updated
    → Alert email is sent

## Installation

### Make the script executable:
```bash
chmod +x watchdog.sh
```

### Configure services.conf:

Format:

```text
NAME HOST PORT MODE THRESHOLD PATH
```


Example:

```text
Google-HTTPS google.com 443 tcp 3 -
Local-HTTP localhost 8000 http 3 /health
```


Note:

**PATH is required only for HTTP mode**

**Use - for TCP mode**


### Configure cron:

Example:
```bash
* * * * * /path/to/watchdog.sh >> /path/to/error.log 2>&1
```


Configure msmtp for email alerts.


## Health Check Mechanism

The script supports two monitoring modes:

### TCP Mode

 - Uses nc (netcat) if available
 - Falls back to Bash /dev/tcp if nc is not installed
 - Verifies port-level connectivity only

### HTTP Mode

 - Uses curl
 - Validates HTTP response codes (2xx–3xx considered healthy)
 - Supports configurable paths

## Requirements

 - Bash 4+
 - curl
 - nc (optional)
 - msmtp
 - cron