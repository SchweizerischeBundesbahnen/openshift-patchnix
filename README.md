OpenShift Patchnix
==================

What is this all about?
-----------------------
We do regular maintenance on our OpenShift clusters. This includes config changes, updating installations, operating system patching and more. In a perfect world, we could do this node after node during office hours. Because of lazy loadbalancers, struggling ha-proxies, stuck cpus, overloaded hardware, locked iptables, internal bugs and not optimal written apps, we simply cannot!

This tool schedules all our maintenance tasks (ansible) for us and stops if something went wrong or looks fishy.

Table of content
----------------
- [OpenShift Patchnix](#openshift-patchnix)
  - [What is this all about?](#what-is-this-all-about)
  - [Table of content](#table-of-content)
  - [How it works](#how-it-works)
  - [A short example](#a-short-example)
  - [Requirements](#requirements)
  - [Installation](#installation)
  - [Config file and parameters](#config-file-and-parameters)
    - [Include and exclude tasks](#include-and-exclude-tasks)
    - [Production namespaces filter (optional)](#production-namespaces-filter-optional)
  - [Ansible phases in detail](#ansible-phases-in-detail)
    - [Phase 0 - Pre-Check: Check if current status is ok](#phase-0---pre-check-check-if-current-status-is-ok)
    - [Phase 1 - Pre-Inform](#phase-1---pre-inform)
    - [Phase 2 - Disable alarms](#phase-2---disable-alarms)
    - [Phase 3 - Maintenance mode](#phase-3---maintenance-mode)
    - [Phase 4 - Config changes](#phase-4---config-changes)
    - [Phase 5 - Updating/Upgrading/Patching](#phase-5---updatingupgradingpatching)
    - [Phase 6 - Checkup](#phase-6---checkup)
    - [Phase 7 - Post-Inform](#phase-7---post-inform)
    - [Phase 8 - Enable alarms](#phase-8---enable-alarms)
    - [Phase 9 - Post run](#phase-9---post-run)
  - [Contribution](#contribution)
  - [Frequently asked questions](#frequently-asked-questions)
    - [How can I list all my patchruns?](#how-can-i-list-all-my-patchruns)
    - [How can I get more information about a certain patchrun?](#how-can-i-get-more-information-about-a-certain-patchrun)
    - [How can I delete a patchrun?](#how-can-i-delete-a-patchrun)
  - [Caveats](#caveats)
    - [Shell environment](#shell-environment)
    - [SSH private key](#ssh-private-key)
  - [License](#license)

How it works
-------------

It basically copies your ansible directory to a new location, creates site.yml and hosts file and schedules some ansible runs with `at`.

You need to define the following input parameters (defaults in brackets):
* start_date (today)
* patchrun_name (empty)
* patch_window_start
* patch_window_end
* servers_per_patch_run (1)
* wait_seconds_between_servers (300)
* servers_in_parallel (1)
* patch_days
* server list

With this parameters, the ruby script `patchrun` then creates the patch-run as follows:
1. It creates a new directory in `patchrun_data` named after the `start_date` and `patchrun_name`. E.g.: 2020-02-29-birthday
2. It copies the ansible directory to the patchrun directory.
3. It creates a new site.yml with the provided variables, included and excluded tasks.
4. It creates a new hosts file from your server list.
5. It checks if `start_date` is today and if `patch_window_start` is already over. In this case, it postpones the first run to tomorrow.
6. Depending on `servers_per_patch_run`, it creates multiple `at` jobs that will run the ansible tasks. The `at` jobs are only scheduled on `patch_days`.
7. The `at` jobs do the real work and execute all the configured ansible tasks.

A short example
---------------
Let's say: 
* You have thirteen servers in your list
* Your patch days are Monday to Friday
* Today is Monday Mar 26 and you run the patchrun command at 15:00

This is your config.yml
```
---
patch_window_start: '00:15:00'
patch_window_end: '04:30:00'
servers_per_patch_run: 3
wait_seconds_between_servers: 300
servers_in_parallel: 1
server_list: server.list
data_dir:
patch_days: # 1 - 7, 1=Monday, 7=Sunday
  - 1 # Monday
  - 2 # Tuesday
  - 3 # Wednesday
  - 4 # Thursday
  - 5 # Friday
force_reboot: false
```
When you create a patchrun like this:
```
./patchrun create
job 266 at Tue Mar 27 00:15:00 2018
job 267 at Wed Mar 28 00:15:00 2018
job 268 at Thu Mar 29 00:15:00 2018
job 269 at Fri Mar 30 00:15:00 2018
job 270 at Mon Apr  2 00:15:00 2018
2018-03-27
```
It creates five at jobs. As `start_date` is not specified, it uses `today` as default. As the `patch_window_start`, which is `00:15:00`, is already over, the first patchday is therefore tomorrow. It creates an `at` job on Tuesday till Friday. As Saturday and Sunday are no `patch_days`, the last `at` job is scheduled on the next Monday.

With patchrun info, you can show details about the scheduled jobs:
```
./patchrun info -p 2018-03-27
-----------------------------------------------
At job: 266     Tue Mar 27 00:15:00 2018 a u225900
At job command: /usr/bin/ansible-playbook site.yml --extra-vars 'mydate=2018-03-27 patch_window_start=00:15:00 patch_window_end=04:30:00 wait_seconds_between_servers=300 servers_in_parallel=1 force_reboot=false' --limit=server1.foobar.com,server2.foobar.com,server3.foobar.com
-----------------------------------------------
At job: 267     Wed Mar 28 00:15:00 2018 a u225900
At job command: /usr/bin/ansible-playbook site.yml --extra-vars 'mydate=2018-03-28 patch_window_start=00:15:00 patch_window_end=04:30:00 wait_seconds_between_servers=300 servers_in_parallel=1 force_reboot=false' --limit=server4.foobar.com,server5.foobar.com,server6.foobar.com
-----------------------------------------------
At job: 268     Thu Mar 29 00:15:00 2018 a u225900
At job command: /usr/bin/ansible-playbook site.yml --extra-vars 'mydate=2018-03-29 patch_window_start=00:15:00 patch_window_end=04:30:00 wait_seconds_between_servers=300 servers_in_parallel=1 force_reboot=false' --limit=server7.foobar.com,server8.foobar.com,server9.foobar.com
-----------------------------------------------
At job: 269     Fri Mar 30 00:15:00 2018 a u225900
At job command: /usr/bin/ansible-playbook site.yml --extra-vars 'mydate=2018-03-30 patch_window_start=00:15:00 patch_window_end=04:30:00 wait_seconds_between_servers=300 servers_in_parallel=1 force_reboot=false' --limit=server10.foobar.com,server11.foobar.com,server12.foobar.com
-----------------------------------------------
At job: 270     Mon Apr  2 00:15:00 2018 a u225900
At job command: /usr/bin/ansible-playbook site.yml --extra-vars 'mydate=2018-04-02 patch_window_start=00:15:00 patch_window_end=04:30:00 wait_seconds_between_servers=300 servers_in_parallel=1 force_reboot=false' --limit=server13.foobar.com
No status file found
Directory: /home/u225900/workspace/openshift-patchnix/patchrun_data/2018-03-27
No logfile found
```

For every sucessfully completed node, ansible will add the nodename to logs/statusfile of the given patchrun job.


Requirements
------------
* Linux system with ansible 2.4 installed
* ssh access to all OpenShift compute nodes (passwordless authentication with keys)
* sudo permissions on all nodes
* Cluster-admin role
* at package installed
* bc package installed
* oc binary installed

Installation
-------------

```
# Clone from github
git clone https://github.com/oscp/openshift-patchnix.git
cd openshift-patchnix

# Install at, bc, oc and mailx
ansible-playbook ansible/tasks/setup.yml

# make patchrun executable
chmod 750 patchrun

# edit config
vi config.yml

# edit serverlist
vi server.list
# This file just contains all your servernames (fqdn), one name per line

# Edit tasks in ansible/tasks/*.yml as you please

# Show help
./patchrun --help

# Create your first patchrun
./patchrun create
```

Config file and parameters
--------------------------

Config file is  config.yml
```
---
patch_window_start: '00:15:00'
patch_window_end: '04:30:00'
servers_per_patch_run: 2
wait_seconds_between_servers: 300
servers_in_parallel: 1
server_list: server.list
data_dir:
patch_days: # 1 - 7, 1=Monday, 7=Sunday
  - 2 # Tuesday
  - 3 # Wednesday
  - 4 # Thursday
  - 5 # Friday
```

You can overwrite all config values with cli parameters expect for the patchdays:
```
Usage: patchrun create|list|info|delete [options]
    -p, --patchrun_name <STRING>     Patchrun name, e.g.: 'kernel-fix' Without whitespaces! (default: empty)
    -t, --start_date <DATE>          Start of the patchrun, e.g.: 2018.02.20 (default: today)
    -s, --patch_window_start <TIME>  Start of the patch window, e.g.: 00:15:00
    -e, --patch_window_end <TIME>    End of the patch window, e.g.: 04:30:00
    -n <INTEGER>,                    How many server to patch in one run. 0=max
        --servers_per_patch_run
    -r <INTEGER>,                    How many server to patch in parallel. Default: 1
        --servers_in_parallel
    -w <SECONDS>,                    How long to wait after a server is patched till we start the next
        --wait_seconds_between_servers
    -l, --server_list <FILE>         File with list of servers to patch
    -i, --include_tasks <STRING>     Comma separated list of tasks to run (in ansible/tasks/*.yml)
    -x, --exclude_tasks <STRING>     Comma separated list of tasks to exclude (in ansible/tasks/*.yml)
    -a, --data_dir <DIRECTORY>       Directory where we put all patchrun information
    -c, --check                      Run ansible in check mode
    -v, --[no-]verbose               Run verbosely
    -d, --[no-]debug                 Run in debug mode

```

### Include and exclude tasks

Include and exclude tasks is implemented as follows:
1. First, all tasks from site.yml are loaded into a hash where the filename of the task is used as key.
2. Secondly, all includes tasks are added to the hash.
3. Finally, all excludes tasks are removed from the hash.

So, exclude always wins!

### Production namespaces filter (optional)
We had some cpu freezing issues evacuating pods. To make sure production pods are less affected by this issue, we evacuate our production pods first. For this to work, ansible needs to know how you name your production namespaces. This is where the `production_namespaces_filter` variables comes into play. We use the postfix `-prod` for our production environments. So we set `production_namespaces_filter: '-prod'` in `ansible/[site|test].yml`. If you don't have such a naming concept, all pods are handled the same.


Ansible phases in detail
-------------------------

All tasks are located in ansible/tasks. They are grouped in phases, which are represented by their nummeric prefixes:
```
ls -1 ansible/tasks/
001_prep_variables.yml
005_precheck_patchwindow.yml
010_precheck_cluster_status.yml
019_precheck_install_cluster_check_tools.yml
020_precheck_cluster_capacity.yml
110_inform_email.yml
120_inform_rocketchat.yml
130_inform_jira.yml
210_alarm_viktorops.yml
220_alarm_newrelic.yml
230_alarm_checkmk.yml
231_alarm_icinga.yml
232_alarm_nagios.yml
240_alarm_zabbix.yml
310_maintenance_unschedule_evacuate_node.yml
410_config_changes.yml
420_config_yum_repositories.yml
510_upgrade_os_only.yml
520_upgrade_all.yml
599_reboot.yml
600_checkup_server_up.yml
610_checkup_services_up.yml
630_checkup_logfiles.yml
680_checkup_schedule_node.yml
690_checkup_pods_running.yml
710_inform_email.yml
720_inform_rocketchat.yml
730_inform_jira.yml
810_alarm_viktorops.yml
820_alarm_newrelic.yml
830_alarm_checkmk.yml
831_alarm_icinga.yml
832_alarm_nagios.yml
840_alarm_zabbix.yml
985_post_add_host_to_statusfile.yml
990_post_wait.yml
setup.yml
```

In Phase 0 we have ansible/tasks/001_prep_variables.yml, which sets the following variables:
```
  set_fact:
    ok: false
    etcd: false
    master: false
    node: false
    gluster: false
    tss: false
    aws: false
    awsprod: false
    awsdev: false
    swisscom: false
    location: ""
    firstmaster: false
```
You probably have different providers and different requirements. So feel free to modify this file to your needs.


### Phase 0 - Pre-Check: Check if current status is ok
1. Prepare some variables
2. Check if cluster-state is OK
  * Are all nodes scheduled?
  * Is there enough capacity to remove a node?

### Phase 1 - Pre-Inform
1. Inform people that the node will be patched soon
  * Email
  * Chat/IRC
  * Jira Ticket
  * ...

### Phase 2 - Disable alarms
1. Disable alarming for node
  * ViktorOps
  * New Relic
  * Check_mk
  * Icinga
  * Nagios
  * Zabbix
  * ...

### Phase 3 - Maintenance mode
1. Disable node scheduling
2. Evacuate production pods first (slowly)
   Note: For this to work, your projects or pods need to have the string '-prod' in the name.
2. Evacuate all other pods (slowly)
3. Check if pods are gone
  * Evacuate again if some pods are still running

### Phase 4 - Config changes
1. Change configuration files
2. Check syntax of changed config files
3. Configure whatever you want here

### Phase 5 - Updating/Upgrading/Patching
1. Pre-patching tasks
  * Disable excluders
  * Update/Change repository
2. Install all new packages
3. Post-patching tasks
  * Check if new kernel is in grub
3. Reboot node

### Phase 6 - Checkup
1. Check if server is up again
2. Check if all services are up and running
3. Check logs for errors
4. Re-schedule node
5. Check if pods are running

### Phase 7 - Post-Inform
1. Inform people that the node is up again
  * Email
  * Chat/IRC
  * Jira Ticket
  * ...

### Phase 8 - Enable alarms
1. Re-enable alarming for node
  * ViktorOps
  * New Relic
  * Check_mk
  * Icinga
  * Nagios
  * Zabbix
  * ...

### Phase 9 - Post run
1. Add completed host to statusfile
2. Wait before we start with the next node

Contribution
------------
A lot of files in ansible/tasks are still empty and there is still plenty of room for new files. If you have cool ideas and other tasks in mind, don't hesitate to send us a pull request!

Frequently asked questions
--------------------------

### How can I list all my patchruns?
```
./patchrun list
2018-03-19-gugus
```

### How can I get more information about a certain patchrun?
```
./patchrun info -p 2018-03-19-gugus
-----------------------------------------------
At job: 246     Mon Mar 26 17:15:00 2018 a u225900
At job command: /usr/bin/ansible-playbook site.yml --extra-vars 'mydate=2018-03-26 patch_window_start=17:15:00 patch_window_end=17:45:00 wait_seconds_between_servers=300 servers_in_parallel=1 force_reboot=false' --limit=server9.foobar.com,server10.foobar.com
-----------------------------------------------
At job: 247     Tue Mar 27 17:15:00 2018 a u225900
At job command: /usr/bin/ansible-playbook site.yml --extra-vars 'mydate=2018-03-27 patch_window_start=17:15:00 patch_window_end=17:45:00 wait_seconds_between_servers=300 servers_in_parallel=1 force_reboot=false' --limit=server11.foobar.com,server12.foobar.com
-----------------------------------------------
At job: 248     Wed Mar 28 17:15:00 2018 a u225900
At job command: /usr/bin/ansible-playbook site.yml --extra-vars 'mydate=2018-03-28 patch_window_start=17:15:00 patch_window_end=17:45:00 wait_seconds_between_servers=300 servers_in_parallel=1 force_reboot=false' --limit=server13.foobar.com
No status file found
Directory: /home/u225900/workspace/openshift-patchnix/patchrun_data/2018-03-19-gugus
Logfile: /home/u225900/workspace/openshift-patchnix/patchrun_data/2018-03-19-gugus/logs/ansible.log

2018-03-22 17:15:01,903 p=29572 u=u225900 |  PLAY RECAP *********************************************************************
2018-03-22 17:15:01,903 p=29572 u=u225900 |  server5.foobar.com             : ok=0    changed=0    unreachable=1    failed=0
2018-03-23 17:15:02,016 p=26114 u=u225900 |  PLAY [all] *********************************************************************
2018-03-23 17:15:02,048 p=26114 u=u225900 |  TASK [Gathering Facts] *********************************************************
2018-03-23 17:15:02,417 p=26114 u=u225900 |  fatal: [server7.foobar.com]: UNREACHABLE! => {"changed": false, "msg": "Failed to connect to the host via ssh: ssh: Could not resolve hostname server7.foobar.com: Name or service not known\r\n", "unreachable": true}
2018-03-23 17:15:02,418 p=26114 u=u225900 |     to retry, use: --limit @/home/u225900/workspace/openshift-patchnix/patchrun_data/2018-03-19-gugus/site.retry

2018-03-23 17:15:02,418 p=26114 u=u225900 |  PLAY RECAP *********************************************************************
2018-03-23 17:15:02,418 p=26114 u=u225900 |  server7.foobar.com             : ok=0    changed=0    unreachable=1    failed=0
```

### How can I delete a patchrun?
```
./patchrun delete -p 2018-03-19-gugus
```

Caveats
-------

### Shell environment
As the `at` job will run ansible, not all variables might be the same as when you run ansible interactively from your shell.

### SSH private key
You need to load your ssh private key into an ssh-agent or store is without a passphrase (not recommended). Otherwise, the at job cannot run ansible tasks on remote machines.

License
-------

Apache License 2.0
