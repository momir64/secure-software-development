import worker

def main(args):
    result = worker.run_command()
    return f"{args} {result}"