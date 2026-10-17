"""Bounded fault injection; no release or provider process is launched."""
import importlib.util
import io
import subprocess
import traceback
import unittest
from pathlib import Path
from unittest.mock import Mock

spec = importlib.util.spec_from_file_location("named", Path(__file__).with_name("check-named-release.py"))
assert spec is not None and spec.loader is not None
named = importlib.util.module_from_spec(spec)
spec.loader.exec_module(named)


class CleanupTest(unittest.TestCase):
    def service(self, failure=None, wait_failure=None):
        service = object.__new__(named.Service)
        service.label = "injected"
        service.process = Mock()
        service.process.poll.return_value = None
        service.process.wait.side_effect = wait_failure
        service.command = Mock()
        if isinstance(failure, Exception):
            service.command.side_effect = failure
        else:
            service.command.return_value.returncode = failure or 0
        service.log = io.StringIO()
        return service

    def test_first_stop_failure_still_cleans_both(self):
        for failure in [RuntimeError("first-stop"), subprocess.TimeoutExpired("stop", 10), 1]:
            with self.subTest(failure=type(failure).__name__):
                first, second = self.service(failure), self.service()
                with self.assertRaises(Exception) as caught:
                    named.stop_services(first, second)
                if isinstance(failure, Exception):
                    self.assertIs(caught.exception, failure)
                else:
                    self.assertIn("stop failed", str(caught.exception))
                for service in [first, second]:
                    service.process.kill.assert_called_once()
                    service.process.wait.assert_any_call(timeout=5)
                    self.assertTrue(service.log.closed)
                second.command.assert_called_once_with("stop")
                second.process.wait.assert_any_call(timeout=10)

    def test_wait_failure_closes_logs_and_reports_both(self):
        failure = subprocess.TimeoutExpired("wait", 5)
        first, second = self.service(RuntimeError("original"), failure), self.service()
        with self.assertRaisesRegex(RuntimeError, "original") as caught:
            named.stop_services(first, second)
        self.assertTrue(first.log.closed and second.log.closed)
        self.assertIn("TimeoutExpired", " ".join(caught.exception.__notes__))
        second.process.wait.assert_any_call(timeout=5)

    def test_both_stop_failures_are_reported(self):
        first, second = self.service(RuntimeError("first")), self.service(ValueError("second"))
        with self.assertRaisesRegex(RuntimeError, "first") as caught:
            named.stop_services(first, second)
        self.assertIn("second", " ".join(caught.exception.__notes__))
        for service in [first, second]:
            service.process.wait.assert_any_call(timeout=5)
            self.assertTrue(service.log.closed)

    def assert_composed_cleanup(self, original=None):
        first_error, second_error = RuntimeError("stop-A"), ValueError("stop-B")
        first = self.service(first_error, subprocess.TimeoutExpired("fallback-A", 5))
        second = self.service(second_error, subprocess.TimeoutExpired("fallback-B", 5))
        with self.assertRaises(Exception) as caught:
            if original is None:
                named.stop_services(first, second)
            else:
                try:
                    raise original
                finally:
                    named.stop_services(first, second)
        final = caught.exception
        self.assertIs(final, original if original is not None else first_error)
        notes = "\n".join(final.__notes__)
        rendered = "".join(traceback.format_exception(final))
        for diagnostic in ["stop-A", "stop-B", "fallback-A", "fallback-B"]:
            self.assertIn(diagnostic, str(final) + "\n" + notes)
            self.assertIn(diagnostic, rendered)
        if original is not None:
            self.assertIn("rpc-composed", rendered)
        for service in [first, second]:
            service.command.assert_called_once_with("stop")
            service.process.kill.assert_called_once_with()
            service.process.wait.assert_called_once_with(timeout=5)
            self.assertTrue(service.log.closed)

    def test_rpc_and_both_services_nested_failures_remain_visible(self):
        self.assert_composed_cleanup(ValueError("rpc-composed"))

    def test_second_service_nested_failure_without_rpc_remains_visible(self):
        self.assert_composed_cleanup()

    def test_primary_rpc_error_is_not_masked(self):
        first, second = self.service(RuntimeError("cleanup")), self.service()
        original = ValueError("rpc-original")
        with self.assertRaises(ValueError) as caught:
            try:
                raise original
            finally:
                named.stop_services(first, second)
        self.assertIs(caught.exception, original)
        self.assertIn("cleanup", " ".join(original.__notes__))
        self.assertTrue(first.log.closed and second.log.closed)


if __name__ == "__main__":
    unittest.main()
