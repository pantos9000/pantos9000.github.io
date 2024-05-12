+++
title = "Per-directory config of git user settings and ssh authentication"
date = 2024-05-04

[taxonomies]
tags = ["git", "ssh"]
+++

# Multiple SSH keys

To generate a new key for a new account or service:

```bash
ssh-keygen -t ed25519 -C "foo@blarb.org" -f "~/.ssh/foo"
ssh-keygen -t ed25519 -C "bar@blubb.org" -f "~/.ssh/bar"
```

# Different SSH keys for different services

If the keys are used for accounts in different services like *github* or *bitbucket*, we can
have each service use a different ssh config.

Add to `~/.ssh/config`:

```bash
Host github.com
    Hostname github.com
    IdentityFile ~/.ssh/foo
    IdentitiesOnly yes

Host bitbucket.org
    Hostname bitbucket.org
    IdentityFile ~/.ssh/bar
    IdentitiesOnly yes
```

Then each service will have a certain SSH key assigned, system-wide. So far so good, but this won't
work for different accounts on the **same** service.

This can be tackled in a different way though, but let's first have alook at...

# Multiple git identities, depending on parent directory

Let's assume we have different git identities (i.e. name/email) for each of the services, and we
want git to automatically choose the right one.

* Create two parent directories that each contains our repos for the according service, e.g.:

  ```bash
  mkdir ~/github
  mkdir ~/bitbucket
  ```

* Add to `~/.gitconfig`:

  ```bash
  [includeIf "gitdir:~/github"]
      path = ~/github/.gitconfig
  [includeIf "gitdir:~/bitbucket"]
      path = ~/bitbucket/.gitconfig
  ```

* Create `~/github/.gitconfig`:

  ```bash
  [user]
      email = foo@blarb.org
      name = Foo
  ```

* Create `~/bitbucket/.gitconfig`:

  ```bash
  [user]
      email = bar@blubb.org
      name = Bar
  ```

With this, git will pick the an identity, depending on the parent directory that the git repo is
in. This will not be system-wide, so if we want to add new identities, we will have to create
additional parent dirs and add new `includeIf` entries.

# Different SSH keys for the same service, depending on parent directory

Instead of using the SSH config file, we can use the different git config files in the respective
parent directories to pick the right SSH key.

* Add to `~/github/.gitconfig`:

  ```bash
  [core]
      sshCommand = ssh -i ~/.ssh/foo
  ```

* Add to `~/bitbucket/.gitconfig`:

  ```bash
  [core]
      sshCommand = ssh -i ~/.ssh/bar
  ```

This can even be used for different git accounts on the same service. Depending on the parent
directory, a certain author, email and ssh key will be used.
