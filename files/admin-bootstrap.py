"""Initialize BookWyrm's required local admin without resetting existing accounts."""
import os


def provision_admin(models, group_model, call_command, transaction, domain, username, email, password, get_representative):
    with transaction.atomic():
        # Serialize concurrent initialization Jobs against the same PostgreSQL DB.
        from django.db import connection
        print("Waiting for the admin initialization database lock...", flush=True)
        with connection.cursor() as cursor:
            cursor.execute("SELECT pg_advisory_xact_lock(%s)", [786421913])
        print("Admin initialization lock acquired; initializing instance data...", flush=True)
        call_command("initdb", verbosity=0)
        # Series imports require this actor before any federation request creates it.
        get_representative()
        print("Instance data ready; provisioning the required administrator...", flush=True)
        user = models.User.objects.filter(localname=username).first()
        if user is None:
            user = models.User.objects.create_user(
                username=f"{username}@{domain}", localname=username, local=True,
                email=email, password=password, is_active=True,
                is_staff=True, is_superuser=True,
            )
            user.groups.add(group_model.objects.get(name="admin"))
            created = True
        else:
            if not (user.local and user.is_active and user.is_staff and user.is_superuser):
                raise RuntimeError("Configured admin username belongs to an account that is not an active local administrator")
            # Preserve its password and profile on repeated initialization.
            user.groups.add(group_model.objects.get(name="admin"))
            created = False
        site = models.SiteSettings.objects.get()
        if site.install_mode:
            site.install_mode = False
            site.save(update_fields=["install_mode"])
    return created


def main():
    from bookwyrm import models
    from bookwyrm.activitypub.base_activity import get_representative
    from bookwyrm.models.fields import validate_localname
    from django.conf import settings
    from django.contrib.auth.models import Group
    from django.core.management import call_command
    from django.core.validators import validate_email
    from django.db import transaction

    print("Validating required admin configuration...", flush=True)
    username = os.environ["BOOKWYRM_ADMIN_USERNAME"]
    email = os.environ["BOOKWYRM_ADMIN_EMAIL"]
    password = os.environ["BOOKWYRM_ADMIN_PASSWORD"]
    validate_localname(username)
    validate_email(email)
    if not password.strip():
        raise RuntimeError("Admin password must not be empty")
    created = provision_admin(models, Group, call_command, transaction, settings.DOMAIN,
                              username, email, password, get_representative)
    print("BookWyrm admin created." if created else "BookWyrm admin already exists; credentials unchanged.")


