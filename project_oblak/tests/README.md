# Security Analyzer Test Scenarios

This directory contains test scenarios for validating all components of the code security analyzer.

| Scenario | Is Safe | Description |
| ---------- | ------------- | ------------- |
| [scenario_1](./scenario_1) | True | Valid scenario with external dependency (`requests`) and file access. |
| [scenario_2](./scenario_2) | False | Malicious scenario using `subprocess.run()` to trigger static analysis. |
| [scenario_3](./scenario_3) | False | Malicious scenario using `eval()` to trigger AST and Bandit detections. |
| [scenario_4](./scenario_4) | True | Sandbox escape attempt using `__globals__` access should result in warning but not block. |
| [scenario_5](./scenario_5) | False | Malware-like payload intended to trigger YARA rules. |
| [scenario_6](./scenario_6) | True | Safe scenario using hashing utilities only. |
| [scenario_7](./scenario_7) | True | Safe scenario demonstrating local file access. |
| [scenario_8](./scenario_8) | False | Malicious scenario that should trigger YARA rules. |
| [scenario_9](./scenario_9) | False | Malicious scenario with broken `requirements.txt` file. |
