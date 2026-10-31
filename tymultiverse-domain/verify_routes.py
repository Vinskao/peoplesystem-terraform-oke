"""Public route contract for tymultiverse.cc and the old host. Read-only GETs, no login.

Run: python tymultiverse-domain/verify_routes.py
"""
import http.client
import ssl
import unittest

OLD = "peoplesystem.tatdvsonorth.com"
NEW = "tymultiverse.cc"

# Non-frontend services must answer the same on both hosts until the old host is retired.
SERVICE_PATHS = [
    "/sso/realms/PeopleSystem/.well-known/openid-configuration",
    "/jenkins/login",
    "/tymb/",
    "/tymg/",
    "/maya-sawa/",
    "/images/people/pair-videos.json",
]


def get(host, path):
    conn = http.client.HTTPSConnection(host, timeout=20, context=ssl.create_default_context())
    try:
        conn.request("GET", path, headers={"User-Agent": "ty-route-check"})
        resp = conn.getresponse()
        resp.read()
        return resp.status, resp.getheader("Location")
    finally:
        conn.close()


class FrontendAtRoot(unittest.TestCase):
    def test_pages_are_served_without_prefix(self):
        for path in ("/", "/about/", "/api/market/dashboard/macro"):
            with self.subTest(path=path):
                self.assertEqual(get(NEW, path)[0], 200)

    def test_unknown_page_is_404_not_home(self):
        self.assertEqual(get(NEW, "/does-not-exist-route-check")[0], 404)

    def test_portfolio_api_stays_behind_auth(self):
        self.assertEqual(get(NEW, "/api/market/portfolio")[0], 401)


class LegacyUrlsRedirect(unittest.TestCase):
    def test_old_host_pages_move_permanently(self):
        cases = {
            "/tymultiverse/work/thread-pool?lang=en": f"https://{NEW}/work/thread-pool?lang=en",
            "/tymultiverse/": f"https://{NEW}/",
            "/": f"https://{NEW}/",
        }
        for path, target in cases.items():
            with self.subTest(path=path):
                self.assertEqual(get(OLD, path), (301, target))

    def test_prefixed_path_on_new_host_moves_to_root(self):
        self.assertEqual(get(NEW, "/tymultiverse/about/"), (301, f"https://{NEW}/about/"))


class ServicesOnBothHosts(unittest.TestCase):
    def test_every_service_answers_like_the_old_host(self):
        for path in SERVICE_PATHS:
            with self.subTest(path=path):
                self.assertEqual(get(NEW, path)[0], get(OLD, path)[0])


if __name__ == "__main__":
    unittest.main(verbosity=2)
