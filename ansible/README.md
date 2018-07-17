OpenShift Patchnix Ansible
==========================

See ../README.md for more information.

Testing
--------

You can test single ansible tasks by adding or removing them in test.yml.

Then, just run:
```
ansible-playbook test.yml -l <YOURHOSTS> --check
```

License
-------

Apache License 2.0

