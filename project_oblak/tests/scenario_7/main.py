def read_message():
    with open("/var/task/message.txt", "r") as file:
        return file.read().strip()

def main(args):
    return args + " " + read_message()