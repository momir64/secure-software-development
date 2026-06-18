import subprocess

def run_command():
    subprocess.run(["ls", "-la"])
    return "done"