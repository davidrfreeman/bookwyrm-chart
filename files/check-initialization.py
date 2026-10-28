"""Read-only readiness check for BookWyrm's required initial administrator."""
import os
from bookwyrm import models
from bookwyrm.settings import INSTANCE_ACTOR_USERNAME

ready = models.User.objects.filter(
    localname=os.environ["BOOKWYRM_ADMIN_USERNAME"],
    local=True, is_active=True, is_staff=True, is_superuser=True,
).exists() and models.SiteSettings.objects.filter(install_mode=False).exists() and models.User.objects.filter(
    localname=INSTANCE_ACTOR_USERNAME, local=True,
).exists()
if not ready:
    raise SystemExit("Admin initialization pending (including instance actor)")
