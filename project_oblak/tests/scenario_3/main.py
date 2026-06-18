def calculate():
    expr = "2 + 2"
    return str(eval(expr))

def main(args):
    result = calculate()
    return f"{args} {result}"