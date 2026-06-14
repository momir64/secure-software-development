import orchestrator
import os

LAMBDA_ID = "test-lambda"
SCRIPT_DIR = str(os.path.join(os.path.dirname(__file__), "test"))


def test_deploy_invoke_destroy():
    orchestrator.startup()
    try:
        orchestrator.deploy(LAMBDA_ID, SCRIPT_DIR)

        result = orchestrator.invoke(LAMBDA_ID, "main.py", "hello")
        print("invoke result:", result)
        assert result.get("exit_code") == 0, f"non-zero exit: {result}"
        assert "hello" in result.get("output", ""), f"unexpected output: {result}"
        assert "test010293" in result.get("output", ""), f"file content missing: {result}"

        orchestrator.destroy(LAMBDA_ID)
        print("test passed")
    finally:
        orchestrator.shutdown()


if __name__ == "__main__":
    test_deploy_invoke_destroy()