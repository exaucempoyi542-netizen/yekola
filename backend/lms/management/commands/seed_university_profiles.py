from django.core.management.base import BaseCommand

from lms.models import University

# Chef-lieu / ville principale par code province
PROVINCE_CITY = {
    "BAS_UELE": "Buta",
    "EQUATEUR": "Mbandaka",
    "HAUT_KATANGA": "Lubumbashi",
    "HAUT_LOMAMI": "Kamina",
    "HAUT_UELE": "Isiro",
    "ITURI": "Bunia",
    "KASAI": "Tshikapa",
    "KASAI_CENTRAL": "Kananga",
    "KASAI_ORIENTAL": "Mbuji-Mayi",
    "KINSHASA": "Kinshasa",
    "KONGO_CENTRAL": "Matadi",
    "KWANGO": "Kenge",
    "KWILU": "Kikwit",
    "LOMAMI": "Kabinda",
    "LUALABA": "Kolwezi",
    "MAI_NDOMBE": "Inongo",
    "MANIEMA": "Kindu",
    "MONGALA": "Lisala",
    "NORD_KIVU": "Goma",
    "NORD_UBANGI": "Gbadolite",
    "SANKURU": "Lodja",
    "SUD_KIVU": "Bukavu",
    "SUD_UBANGI": "Gemena",
    "TANGANYIKA": "Kalemie",
    "TSHOPO": "Kisangani",
    "TSHUAPA": "Boende",
}


def _slug_email(name: str) -> str:
    import re
    import unicodedata

    text = unicodedata.normalize("NFKD", name)
    text = "".join(c for c in text if not unicodedata.combining(c))
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", "-", text).strip("-")
    return text[:40] or "universite"


class Command(BaseCommand):
    help = "Remplit adresse, téléphone, email et capacité des universités si vides."

    def handle(self, *args, **options):
        updated = 0
        for uni in University.objects.select_related("province").all():
            code = uni.province.code if uni.province_id else "KINSHASA"
            city = PROVINCE_CITY.get(code, "RDC")
            province_name = uni.province.name if uni.province_id else "RDC"
            slug = _slug_email(uni.name)
            fields = []

            if not (uni.address or "").strip():
                uni.address = f"Avenue de l'Université, {city}, {province_name}, RDC"
                fields.append("address")

            if not (uni.phone or "").strip():
                # Numéro fictif stable dérivé de l'id
                uni.phone = f"+243 81 {100 + (uni.pk % 800):03d} {1000 + (uni.pk % 9000):04d}"
                fields.append("phone")

            if not (uni.email or "").strip():
                uni.email = f"contact@{slug}.ac.cd"
                fields.append("email")

            if uni.capacity is None:
                base = 8000 if uni.institution_type == "PUBLIC" else 2500
                uni.capacity = base + (uni.pk % 17) * 250
                fields.append("capacity")

            if fields:
                uni.save(update_fields=fields)
                updated += 1
                self.stdout.write(f"  ~ {uni.name} ({', '.join(fields)})")

        self.stdout.write(self.style.SUCCESS(f"\n{updated} universite(s) mises a jour."))
