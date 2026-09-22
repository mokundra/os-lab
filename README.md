# Laboratory Work #1

## Description

This project implements automatic log storage management for an information system consisting of three services:

- `auth_service`
- `data_process_service`
- `system_event_handler_service`

Log files are stored in:

```text
/LOGS/auth_service/
/LOGS/data_process_service/
/LOGS/system_event_handler_service/
```

The `/LOGS` directory is mounted on a separate disk partition.

If the partition usage exceeds the configured limit, the cleanup script checks the size of each service directory. The available log storage limit is divided equally between the three services.

Only service directories that exceed their allowed 1/3 limit are cleaned.

The oldest `.log` files are archived into `.tar.gz` files and deleted only after successful archive creation and verification.

---

## Project files

### `cleanup.sh`

Main cleanup script.

It:

- checks that `/LOGS` is mounted;
- checks partition usage;
- compares usage with the configured limit;
- divides the allowed log storage between three services;
- finds overloaded service directories;
- selects the oldest log files;
- creates `.tar.gz` archives;
- verifies created archives;
- deletes archived log files.

Default usage limit:

```text
90%
```

Example:

```bash
./cleanup.sh /LOGS 90 ./backup
```

---

### `test_cleanup.sh`

Automatic test script.

The tests create a temporary environment, generate log files, run `cleanup.sh`, and verify the result.

The test scenarios include:

- no cleanup when partition usage is below the limit;
- cleanup of only one overloaded service;
- verification that the oldest log file is archived first;
- cleanup of two overloaded services;
- behavior when partition usage is exactly equal to the limit;
- invalid environment and configuration cases.

Run:

```bash
./test_cleanup.sh
```

Successful result:

```text
ALL TESTS PASSED
```

---

### `mount_logs.sh`

Script for mounting the LOGS partition.

The device is passed as an argument.

Linux example:

```bash
sudo ./mount_logs.sh /dev/sdb1 /LOGS
```

WSL / Windows drive example:

```bash
sudo ./mount_logs.sh E: /LOGS
```

The script automatically detects whether the passed device is a Windows drive or a Linux block device.

After mounting, it creates:

```text
/LOGS/auth_service
/LOGS/data_process_service
/LOGS/system_event_handler_service
```

---

### `mount-logs.service`

Systemd service used to run `mount_logs.sh` automatically when the operating system starts.

The service runs the script from:

```text
/usr/local/bin/mount_logs.sh
```

---

### `mount-logs.conf.example`

Example configuration:

```bash
DEVICE=/dev/sdb1
MOUNTDIR=/LOGS
```

For WSL:

```bash
DEVICE=E:
MOUNTDIR=/LOGS
```

---

## Permissions

Make the shell scripts executable:

```bash
chmod +x cleanup.sh
chmod +x test_cleanup.sh
chmod +x mount_logs.sh
```

---

## Install mount script

Copy `mount_logs.sh` to a system-wide location:

```bash
sudo cp mount_logs.sh /usr/local/bin/mount_logs.sh
sudo chmod +x /usr/local/bin/mount_logs.sh
```

---

## Configure mount device

Copy the example configuration:

```bash
sudo cp mount-logs.conf.example /etc/default/mount-logs
```

Edit it:

```bash
sudo nano /etc/default/mount-logs
```

Linux example:

```bash
DEVICE=/dev/sdb1
MOUNTDIR=/LOGS
```

WSL example:

```bash
DEVICE=E:
MOUNTDIR=/LOGS
```

The device is configured separately, so the systemd service does not depend on a specific disk or drive letter.

---

## Automatic mounting

Copy the systemd service:

```bash
sudo cp mount-logs.service /etc/systemd/system/
```

Reload systemd:

```bash
sudo systemctl daemon-reload
```

Enable automatic startup:

```bash
sudo systemctl enable mount-logs.service
```

Start the service:

```bash
sudo systemctl start mount-logs.service
```

Check its status:

```bash
systemctl status mount-logs.service
```

Expected service state:

```text
active (exited)
```

Check that `/LOGS` is mounted:

```bash
mountpoint /LOGS
```

Expected result:

```text
/LOGS is a mountpoint
```

Check service directories:

```bash
ls /LOGS
```

The following directories should exist:

```text
auth_service
data_process_service
system_event_handler_service
```

---

## Cleanup

Run the cleanup script:

```bash
./cleanup.sh /LOGS 90 ./backup
```

Arguments:

1. LOGS directory
2. partition usage limit in percent
3. backup directory

The backup directory must not be located inside the `/LOGS` partition.

---

## Testing

Run:

```bash
./test_cleanup.sh
```

Expected final output:

```text
ALL TESTS PASSED
```

The test script automatically creates the test environment and checks both positive and negative scenarios.
