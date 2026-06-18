from lib import hello_world, fetch_todo

def main(args):
    todo = fetch_todo()
    return args + " " + hello_world() + " " + str(todo)