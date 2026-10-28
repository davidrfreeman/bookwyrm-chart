import importlib.util
from contextlib import nullcontext
from pathlib import Path
from types import ModuleType, SimpleNamespace
import sys
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('admin_bootstrap', Path(__file__).parents[1] / 'files/admin-bootstrap.py')
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)


class AdminTests(unittest.TestCase):
    def setUp(self):
        self.cursor = Mock()
        connection = Mock()
        connection.cursor.return_value.__enter__ = Mock(return_value=self.cursor)
        connection.cursor.return_value.__exit__ = Mock(return_value=False)
        db = ModuleType('django.db')
        db.connection = connection
        self.modules = patch.dict(sys.modules, {'django': ModuleType('django'), 'django.db': db})
        self.modules.start()
        self.addCleanup(self.modules.stop)
        self.user = Mock(local=True, is_active=True, is_staff=True, is_superuser=True)
        self.site = SimpleNamespace(install_mode=True, save=Mock())
        self.models = SimpleNamespace(User=Mock(), SiteSettings=Mock())
        self.models.User.objects.filter.return_value.first.return_value = None
        self.models.User.objects.create_user.return_value = self.user
        self.models.SiteSettings.objects.get.return_value = self.site
        self.group = Mock()
        self.initdb = Mock()
        self.get_representative = Mock()

    def provision(self):
        return bootstrap.provision_admin(self.models, self.group, self.initdb,
            SimpleNamespace(atomic=nullcontext), 'books.example.com', 'owner',
            'owner@example.com', 'initial-password', self.get_representative)

    def test_initial_account_is_local_admin_and_setup_is_closed(self):
        self.assertTrue(self.provision())
        self.models.User.objects.create_user.assert_called_once_with(
            username='owner@books.example.com', localname='owner', local=True,
            email='owner@example.com', password='initial-password',
            is_active=True, is_staff=True, is_superuser=True)
        self.initdb.assert_called_once_with('initdb', verbosity=0)
        self.get_representative.assert_called_once_with()
        self.user.groups.add.assert_called_once_with(self.group.objects.get.return_value)
        self.assertFalse(self.site.install_mode)
        self.site.save.assert_called_once_with(update_fields=['install_mode'])
        self.cursor.execute.assert_called_once_with('SELECT pg_advisory_xact_lock(%s)', [786421913])

    def test_existing_admin_credentials_are_unchanged(self):
        self.models.User.objects.filter.return_value.first.return_value = self.user
        self.assertFalse(self.provision())
        self.get_representative.assert_called_once_with()
        self.models.User.objects.create_user.assert_not_called()
        self.user.set_password.assert_not_called()
        self.user.save.assert_not_called()

    def test_existing_regular_account_is_not_promoted(self):
        self.user.is_superuser = False
        self.models.User.objects.filter.return_value.first.return_value = self.user
        with self.assertRaisesRegex(RuntimeError, 'not an active local administrator'):
            self.provision()
        self.user.groups.add.assert_not_called()
        self.assertTrue(self.site.install_mode)
        self.models.User.objects.create_user.assert_not_called()

    def test_inactive_admin_is_not_reactivated(self):
        self.user.is_active = False
        self.models.User.objects.filter.return_value.first.return_value = self.user
        with self.assertRaises(RuntimeError):
            self.provision()
        self.user.save.assert_not_called()
        self.assertTrue(self.site.install_mode)
