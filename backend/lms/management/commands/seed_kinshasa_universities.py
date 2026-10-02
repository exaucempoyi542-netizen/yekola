from django.core.management.base import BaseCommand

from lms.models import Province, University


# province_code -> [(name, institution_type), ...]
UNIVERSITIES_BY_PROVINCE = {
    "KINSHASA": [
        ("Université de Kinshasa (UNIKIN)", "PUBLIC"),
        ("Université Pédagogique Nationale (UPN)", "PUBLIC"),
        ("Université des Sciences de l'Information et de la Communication (UNISIC)", "PUBLIC"),
        ("Université Protestante au Congo (UPC)", "PRIVATE"),
        ("Université Catholique au Congo (UCC)", "PRIVATE"),
        ("Université William Booth (UWB)", "PRIVATE"),
        ("Université Libre de Kinshasa (ULK)", "PRIVATE"),
        ("Université Chrétienne Cardinal Malula (UCCM)", "PRIVATE"),
        ("Université Cardinal Malula (UCM)", "PRIVATE"),
        ("Université Adventiste au Congo (UACO)", "PRIVATE"),
        ("Université Africaine de Développement (UAD)", "PRIVATE"),
        ("Université Canadienne au Congo (UCAC)", "PRIVATE"),
        ("Université Cartésienne de Kinshasa", "PRIVATE"),
        ("Université Catholique Don Peti Peti (UNICAP)", "PRIVATE"),
        ("Université Chrétienne Catholique Don Akam", "PRIVATE"),
        ("Université Chrétienne de Kinshasa (UCKIN)", "PRIVATE"),
        ("Université du CEPROMAD (UNIC)", "PRIVATE"),
        ("Université du Plateau de Batéké (UPB)", "PRIVATE"),
        ("Université Franco-Américaine de Kinshasa (UFAK)", "PRIVATE"),
        ("Université Libre Bilingue de Kinshasa (ULBK)", "PRIVATE"),
        ("Université Libre Protestante d'Afrique (ULPA)", "PRIVATE"),
        ("Université Liloba na Nzambe au Congo (UNLC)", "PRIVATE"),
        ("Université Loyola du Congo (ULC)", "PRIVATE"),
        ("Université Progrès de Kinshasa-Est (UPK-E)", "PRIVATE"),
        ("Université Progressiste de Kinshasa", "PRIVATE"),
        ("Université Révérend Kim (URK)", "PRIVATE"),
        ("Université Richfield (UR)", "PRIVATE"),
        ("Université Saint Augustin de Kinshasa (USAKIN)", "PRIVATE"),
        ("Université Saint Dominique de Kinshasa (USD)", "PRIVATE"),
    ],
    "HAUT_KATANGA": [
        ("Université de Lubumbashi (UNILU)", "PUBLIC"),
        ("Université de Likasi (UNILIK)", "PUBLIC"),
        ("Université Don Bosco de Lubumbashi", "PRIVATE"),
        ("Université Maria Malkia", "PRIVATE"),
        ("Université Panafricaine de Lubumbashi", "PRIVATE"),
        ("Université ILYS de Lubumbashi", "PRIVATE"),
        ("Université Saint François", "PRIVATE"),
        ("Université de Kamina", "PUBLIC"),
    ],
    "LUALABA": [
        ("Université de Kolwezi", "PUBLIC"),
        ("Université Jean XXIII de Kolwezi", "PRIVATE"),
        ("Université Protestante de Kolwezi", "PRIVATE"),
    ],
    "HAUT_LOMAMI": [
        ("Université de Kamina", "PUBLIC"),
        ("Université de Malemba-Nkulu", "PUBLIC"),
        ("Université de Bukama", "PUBLIC"),
    ],
    "TANGANYIKA": [
        ("Université de Kalemie", "PUBLIC"),
        ("Université Patrice Emery Lumumba de Kalemie", "PUBLIC"),
        ("Université Saint Joseph de Kalemie", "PRIVATE"),
        ("Université de Manono", "PUBLIC"),
    ],
    "NORD_KIVU": [
        ("Université de Goma (UNIGOM)", "PUBLIC"),
        ("Université Catholique du Graben (UCG)", "PRIVATE"),
        ("Université Libre des Pays des Grands Lacs (ULPGL)", "PRIVATE"),
        ("Université Protestante en Afrique", "PRIVATE"),
        ("Université Saint Joseph de Goma", "PRIVATE"),
        ("Université de Béni", "PUBLIC"),
        ("Université de Butembo", "PUBLIC"),
        ("Université de l'Assomption au Congo", "PRIVATE"),
    ],
    "SUD_KIVU": [
        ("Université Catholique de Bukavu (UCB)", "PRIVATE"),
        ("Université Officielle de Bukavu (UOB)", "PUBLIC"),
        ("Université Evangélique en Afrique (UEA)", "PRIVATE"),
        ("Université Anglicane de Bukavu", "PRIVATE"),
        ("Université Francophone d'Uvira", "PRIVATE"),
        ("Université Protestante Évangélique de Bukavu", "PRIVATE"),
        ("Université Roi Baudouin de Kadutu", "PRIVATE"),
    ],
    "MANIEMA": [
        ("Université de Kindu (UNIKI)", "PUBLIC"),
        ("Université Catholique du Maniema", "PRIVATE"),
        ("Université Protestante du Maniema", "PRIVATE"),
        ("Université Géoscience du Maniema", "PRIVATE"),
    ],
    "TSHOPO": [
        ("Université de Kisangani (UNIKIS)", "PUBLIC"),
        ("Université de l'Uélé", "PUBLIC"),
        ("Faculté Universitaire de Bambelota", "PUBLIC"),
        ("Université de Yangambi", "PUBLIC"),
    ],
    "ITURI": [
        ("Université de Bunia (UNIBU)", "PUBLIC"),
        ("Université de l'Ituri", "PUBLIC"),
        ("Université de Shalom de Bunia", "PRIVATE"),
        ("Université Saint-Pierre de Bunia", "PRIVATE"),
        ("Université du CEPROMAD de Bunia", "PRIVATE"),
    ],
    "HAUT_UELE": [
        ("Université de l'Uélé", "PUBLIC"),
        ("Université de l'Isiro", "PUBLIC"),
        ("Université Saint Joseph de Dungu", "PRIVATE"),
        ("Université Saint Joseph de Watsa", "PRIVATE"),
        ("Université Saint Joseph d'Isiro", "PRIVATE"),
    ],
    "BAS_UELE": [
        ("Université de Buta", "PUBLIC"),
        ("Université de Bambili", "PUBLIC"),
        ("Centres universitaires et instituts supérieurs de Buta", "PUBLIC"),
    ],
    "EQUATEUR": [
        ("Université de Mbandaka", "PUBLIC"),
        ("Université de l'Équateur", "PUBLIC"),
        ("Université Protestante de Mbandaka", "PRIVATE"),
    ],
    "MONGALA": [
        ("Université de Lisala", "PUBLIC"),
        ("Université de la Mongala", "PUBLIC"),
    ],
    "NORD_UBANGI": [
        ("Université de Gbadolite", "PUBLIC"),
        ("Université de Nord-Ubangi", "PUBLIC"),
    ],
    "SUD_UBANGI": [
        ("Université de Gemena", "PUBLIC"),
        ("Université Protestante de Gemena", "PRIVATE"),
    ],
    "TSHUAPA": [
        ("Université de Boende", "PUBLIC"),
        ("Université de Tshuapa", "PUBLIC"),
    ],
    "KONGO_CENTRAL": [
        ("Université Kongo (UK)", "PUBLIC"),
        ("Université Président Joseph Kasa-Vubu", "PUBLIC"),
        ("Université de Matadi", "PUBLIC"),
        ("Université Francophone d'Afrique de Matadi", "PRIVATE"),
        ("Université de Boma", "PUBLIC"),
    ],
    "KWILU": [
        ("Université de Bandundu", "PUBLIC"),
        ("Université Catholique du Grand Bandundu", "PRIVATE"),
        ("Université de Kikwit", "PUBLIC"),
    ],
    "KWANGO": [
        ("Université de Kenge", "PUBLIC"),
        ("Université du Kwango", "PUBLIC"),
    ],
    "MAI_NDOMBE": [
        ("Université de Mai-Ndombe", "PUBLIC"),
        ("Université d'Inongo", "PUBLIC"),
    ],
    "KASAI_CENTRAL": [
        ("Université de Kananga (UNIKAN)", "PUBLIC"),
        ("Université Notre-Dame du Kasaï", "PRIVATE"),
        ("Université Saint Laurent de Kananga", "PRIVATE"),
        ("Université Saint Joseph de Kamutanga", "PRIVATE"),
    ],
    "KASAI": [
        ("Université de Tshikapa", "PUBLIC"),
        ("Université du Kasaï", "PUBLIC"),
        ("Université de Mweka", "PUBLIC"),
    ],
    "KASAI_ORIENTAL": [
        ("Université Officielle de Mbuji-Mayi (UOM)", "PUBLIC"),
        ("Université de Mbuji-Mayi", "PUBLIC"),
        ("Université Protestante de Mbuji-Mayi", "PRIVATE"),
    ],
    "LOMAMI": [
        ("Université de Kabinda", "PUBLIC"),
        ("Université Notre-Dame de Lomami", "PRIVATE"),
        ("Université de Mwene-Ditu", "PUBLIC"),
    ],
    "SANKURU": [
        ("Université de Lodja", "PUBLIC"),
        ("Université de Lusambo", "PUBLIC"),
        ("Université Logos Dei du Congo", "PRIVATE"),
        ("Université Panafricaine du Sankuru", "PRIVATE"),
        ("Université Notre-Dame de Tshumbe", "PRIVATE"),
    ],
}

ALIASES = {
    "KINSHASA": {
        "WILLIAM BOOTH": "Université William Booth (UWB)",
        "William Booth": "Université William Booth (UWB)",
        "Université William Booth": "Université William Booth (UWB)",
        "UNIKIN": "Université de Kinshasa (UNIKIN)",
        "Université de Kinshasa": "Université de Kinshasa (UNIKIN)",
        "UPN": "Université Pédagogique Nationale (UPN)",
    },
}


class Command(BaseCommand):
    help = "Ajoute les universités par province (RDC) sans doublons."

    def add_arguments(self, parser):
        parser.add_argument(
            "--province",
            type=str,
            default="",
            help="Code province uniquement (ex. HAUT_KATANGA). Vide = toutes.",
        )

    def handle(self, *args, **options):
        only = (options.get("province") or "").strip().upper()
        data = UNIVERSITIES_BY_PROVINCE
        if only:
            if only not in data:
                self.stderr.write(self.style.ERROR(f"Province inconnue : {only}"))
                return
            data = {only: data[only]}

        grand_created = 0
        grand_updated = 0
        grand_skipped = 0

        for code, universities in data.items():
            province, _ = Province.objects.get_or_create(code=code)
            created = updated = skipped = 0

            for old_name, new_name in ALIASES.get(code, {}).items():
                qs = University.objects.filter(province=province, name__iexact=old_name)
                for uni in qs:
                    if uni.name == new_name:
                        continue
                    target = (
                        University.objects.filter(province=province, name=new_name)
                        .exclude(pk=uni.pk)
                        .first()
                    )
                    if target:
                        uni.delete()
                        self.stdout.write(f"  [{province.name}] Alias fusionne : {old_name} -> {new_name}")
                    else:
                        uni.name = new_name
                        uni.save(update_fields=["name"])
                        updated += 1
                        self.stdout.write(f"  [{province.name}] Renomme : {old_name} -> {new_name}")

            self.stdout.write(self.style.NOTICE(f"\n== {province.name} ({code}) =="))
            for name, institution_type in universities:
                uni, was_created = University.objects.get_or_create(
                    name=name,
                    province=province,
                    defaults={"institution_type": institution_type},
                )
                if was_created:
                    created += 1
                    self.stdout.write(f"  + {name} ({institution_type})")
                elif uni.institution_type != institution_type:
                    uni.institution_type = institution_type
                    uni.save(update_fields=["institution_type"])
                    updated += 1
                    self.stdout.write(f"  ~ type : {name}")
                else:
                    skipped += 1

            total = University.objects.filter(province=province).count()
            self.stdout.write(
                f"  -> {created} creees, {updated} maj, {skipped} existantes. Total = {total}"
            )
            grand_created += created
            grand_updated += updated
            grand_skipped += skipped

        self.stdout.write(
            self.style.SUCCESS(
                f"\nTOTAL : {grand_created} creees, {grand_updated} maj, "
                f"{grand_skipped} deja presentes."
            )
        )
