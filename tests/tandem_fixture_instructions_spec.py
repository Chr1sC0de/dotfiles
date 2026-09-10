"""Check that the deterministic model fixture detects conflicting live instructions."""

import copy
import unittest
from pathlib import Path

from tandem_integration import ModelFixture


class InstructionChecks(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = ModelFixture(Path.cwd())
        self.body = {
            "model": "gpt-6-astra",
            "reasoning": {"effort": "high"},
            "input": [
                {
                    "role": "developer",
                    "content": [
                        {
                            "type": "input_text",
                            "text": "TANDEM_HOST_INSTRUCTION_MARKER: Use tandem_write_file for edits.",
                        }
                    ],
                },
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "input_text",
                            "text": (
                                "Historical reference: TANDEM_READONLY_TEST READONLY_DONE. "
                                "Previous answer: Analysis-only Tandem session. Do not edit files.\n"
                                "New instruction: TANDEM_FOLLOWUP_TEST implement the change."
                            ),
                        }
                    ],
                },
            ],
        }

    def test_historical_refusal_is_reference_context(self) -> None:
        result = self.fixture.answer(self.body)
        self.assertEqual(result["call_id"], "followup-native")

    def test_retained_developer_instruction_fails_before_tool_call(self) -> None:
        # Reproduce the broken resume: writer guidance plus the old developer message.
        self.body["input"].insert(
            0,
            {
                "role": "developer",
                "content": [
                    {
                        "type": "input_text",
                        "text": "Analysis-only Tandem session. Do not edit files.",
                    }
                ],
            },
        )
        with self.assertRaisesRegex(
            AssertionError, "analysis-only developer instruction"
        ):
            self.fixture.answer(self.body)
        self.assertEqual(self.fixture.trace, [])

    def test_top_level_instruction_conflict_is_checked(self) -> None:
        self.body["instructions"] = "Analysis-only Tandem session. Do not edit files."
        with self.assertRaisesRegex(
            AssertionError, "analysis-only developer instruction"
        ):
            self.fixture.answer(self.body)
        self.assertEqual(self.fixture.trace, [])

    def test_host_guidance_must_survive(self) -> None:
        self.body["input"][0]["content"][0]["text"] = "Use tandem_write_file."
        with self.assertRaisesRegex(AssertionError, "host instructions were lost"):
            self.fixture.answer(self.body)

    def test_writer_guidance_is_required(self) -> None:
        self.body["input"][0]["content"][0]["text"] = "TANDEM_HOST_INSTRUCTION_MARKER"
        with self.assertRaisesRegex(AssertionError, "edit guidance is missing"):
            self.fixture.answer(self.body)

    def test_continuing_edit_thread_rechecks_instructions(self) -> None:
        body = copy.deepcopy(self.body)
        body["input"].append(
            {"role": "user", "content": "FOLLOWUP_DONE TANDEM_CONTINUE_TEST summarize"}
        )
        result = self.fixture.answer(body)
        self.assertEqual(result["content"][0]["text"], "CONTINUE_DONE")


if __name__ == "__main__":
    unittest.main()
