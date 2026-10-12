import sys

content = open('lib/widgets/fantasy/pitch_view.dart', 'r', encoding='utf-8').read()
import_str = "import '../../models/fantasy_models.dart';\nimport '../../services/fantasy_scout_service.dart';"
content = content.replace("import '../../models/fantasy_models.dart';", import_str)
open('lib/widgets/fantasy/pitch_view.dart', 'w', encoding='utf-8').write(content)
print("Done")
