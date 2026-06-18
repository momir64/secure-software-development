def inspect_globals():
    return str(inspect_globals.__globals__.keys())

def main(args):
    return args + " " + inspect_globals()