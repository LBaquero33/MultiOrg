from pathlib import Path
import subprocess
root = Path('/Users/lb33/Downloads/HomePlate-iOS-Native')
work = root / 'work/remediation'
def declaration(path: str, marker: str) -> str:
    source = (root / path).read_text(); start = source.index(marker); brace = source.index('{', start); depth = 0
    for index in range(brace, len(source)):
        if source[index] == '{': depth += 1
        elif source[index] == '}':
            depth -= 1
            if depth == 0: return source[start:index + 1]
    raise ValueError(f'unclosed declaration: {marker}')
parts = ['import Foundation']
for path, marker in [
    ('HomePlate/Core/OrgModels.swift', 'struct SDOrgMembership:'),
    ('HomePlate/Core/OrgModels.swift', 'enum OrganizationAuthorization'),
    ('HomePlate/Core/OrgModels.swift', 'enum SDChatAuthorization'),
    ('HomePlate/Core/OrgModels.swift', 'enum SDJSONValue:'),
    ('HomePlate/Core/GameModels.swift', 'enum SDGameLifecycle:'),
    ('HomePlate/Core/TeamOperationsModels.swift', 'enum HPTeamWorkspaceSection:'),
    ('HomePlate/Core/TeamOperationsModels.swift', 'struct HPTeamWorkspaceRoute:'),
    ('HomePlate/Core/TeamOperationsModels.swift', 'enum HPCalendarLinkSource:'),
    ('HomePlate/Core/TeamOperationsModels.swift', 'enum HPCalendarLinkError:'),
    ('HomePlate/Core/TeamOperationsModels.swift', 'struct HPCalendarLinkRoute:'),
    ('HomePlate/Core/TeamOperationsModels.swift', 'private struct HPDeepLinkQueryValues'),
    ('HomePlate/Core/OrganizationSetupModels.swift', 'struct SDParentInviteRedemption:'),
]: parts.append(declaration(path, marker))
(work / 'native_contract_extracted.swift').write_text('\n\n'.join(parts) + '\n')
binary = work / 'native_contract_harness'
subprocess.run(['swiftc', '-parse-as-library', str(root / 'HomePlate/Core/GameScoringEngine.swift'), str(root / 'HomePlate/Core/GameRuleset.swift'), str(root / 'HomePlate/Core/GameScorekeeperSession.swift'), str(root / 'HomePlate/Core/GameScoringJournal.swift'), str(work / 'native_contract_extracted.swift'), str(work / 'native_contract_harness.swift'), '-o', str(binary)], cwd=root, check=True)
subprocess.run([str(binary)], cwd=root, check=True)
