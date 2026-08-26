-- アプリ画面確認 v9
-- GitHub上のExpoアプリを選び、iPhone / Androidで確認します。

property appVersion : "v9"
property appsRoot : (POSIX path of (path to home folder)) & "Library/Application Support/アプリ画面確認/アプリ"
property keychainService : "アプリ画面確認-GitHub"
property keychainAccount : "github-token"
property launchLog : "/tmp/app-screen-check.log"

on run
	display dialog "起動しています…" with title "アプリ画面確認" buttons {} giving up after 1
	set githubToken to my getGitHubToken()
	if githubToken is "" then return
	my ensureFolder(appsRoot)
	display notification "GitHubからアプリを確認しています" with title "アプリ画面確認"
	
	set appRecords to my findExpoRepositories(githubToken)
	if (count of appRecords) is 0 then
		display alert "アプリが見つかりません" message "GitHub上にExpoアプリとして判定できるリポジトリが見つかりませんでした。"
		return
	end if
	
	set appLabels to {}
	repeat with appRecord in appRecords
		set end of appLabels to item 1 of appRecord
	end repeat
	set selectedApp to choose from list appLabels with title "アプリ画面確認 " & appVersion with prompt "確認するアプリを選んでください" OK button name "次へ" cancel button name "キャンセル"
	if selectedApp is false then return
	set selectedLabel to item 1 of selectedApp
	set selectedIndex to my indexOf(selectedLabel, appLabels)
	set selectedRecord to item selectedIndex of appRecords
	set repoName to item 2 of selectedRecord
	set repoFullName to item 3 of selectedRecord
	set expoSubPath to item 4 of selectedRecord
	
	set deviceChoice to choose from list {"iPhone", "Android"} with title "アプリ画面確認" with prompt "どちらで確認しますか？" OK button name "開く" cancel button name "キャンセル"
	if deviceChoice is false then return
	set deviceName to item 1 of deviceChoice
	
	set repoPath to appsRoot & "/" & repoName
	display notification "最新版を準備しています" with title "アプリ画面確認"
	if my prepareRepository(repoFullName, repoPath, githubToken) is false then return
	if expoSubPath is "" then
		set expoPath to repoPath
	else
		set expoPath to repoPath & "/" & expoSubPath
	end if
	my launchExpo(expoPath, deviceName, selectedLabel)
end run

on getGitHubToken()
	try
		set savedToken to do shell script "security find-generic-password -s " & quoted form of keychainService & " -a " & quoted form of keychainAccount & " -w"
		if savedToken is not "" then return savedToken
	end try
	set tokenDialog to display dialog "GitHubの読み取り用トークンを入力してください。" default answer "" with title "アプリ画面確認" buttons {"キャンセル", "保存"} default button "保存" with hidden answer
	if button returned of tokenDialog is not "保存" then return ""
	set githubToken to text returned of tokenDialog
	if githubToken is "" then return ""
	try
		do shell script "security add-generic-password -U -s " & quoted form of keychainService & " -a " & quoted form of keychainAccount & " -w " & quoted form of githubToken
		return githubToken
	on error errorMessage
		display alert "トークンを保存できませんでした" message errorMessage
		return ""
	end try
end getGitHubToken

on findExpoRepositories(githubToken)
	set reposUrl to "https://api.github.com/user/repos?per_page=100&sort=updated&affiliation=owner"
	try
		set reposJson to do shell script my apiCommand(githubToken, reposUrl, "application/vnd.github+json")
	on error errorMessage
		display alert "GitHubから取得できませんでした" message errorMessage
		return {}
	end try
	set jsCode to "ObjC.import('stdlib'); const r=JSON.parse($.getenv('REPOS_JSON')); r.filter(x=>!x.archived).map(x=>[x.name,x.full_name,x.default_branch].join('\\t')).join('\\n')"
	try
		set repoText to do shell script "REPOS_JSON=" & quoted form of reposJson & " /usr/bin/osascript -l JavaScript -e " & quoted form of jsCode
	on error
		return {}
	end try
	if repoText is "" then return {}
	set results to {}
	repeat with repoLine in paragraphs of repoText
		set oldTID to AppleScript's text item delimiters
		set AppleScript's text item delimiters to tab
		set parts to text items of repoLine
		set AppleScript's text item delimiters to oldTID
		if (count of parts) >= 3 then
			set repoName to item 1 of parts
			set repoFullName to item 2 of parts
			set defaultBranch to item 3 of parts
			set expoInfo to my findExpoInRepo(githubToken, repoFullName, defaultBranch)
			if expoInfo is not false then
				set appName to item 1 of expoInfo
				set expoSubPath to item 2 of expoInfo
				if expoSubPath is "" then
					set appLabel to repoName
				else
					set appLabel to repoName & " / " & appName
				end if
				set end of results to {appLabel, repoName, repoFullName, expoSubPath}
			end if
		end if
	end repeat
	return results
end findExpoRepositories

on findExpoInRepo(githubToken, repoFullName, defaultBranch)
	set treeUrl to "https://api.github.com/repos/" & repoFullName & "/git/trees/" & defaultBranch & "?recursive=1"
	try
		set treeJson to do shell script my apiCommand(githubToken, treeUrl, "application/vnd.github+json")
	on error
		return false
	end try
	set jsCode to "ObjC.import('stdlib'); const t=(JSON.parse($.getenv('TREE_JSON')).tree||[]); t.filter(x=>x.type==='blob' && x.path.endsWith('package.json') && x.path.split('/').length<=3).map(x=>x.path).join('\\n')"
	try
		set packageText to do shell script "TREE_JSON=" & quoted form of treeJson & " /usr/bin/osascript -l JavaScript -e " & quoted form of jsCode
	on error
		return false
	end try
	if packageText is "" then return false
	repeat with packagePath in paragraphs of packageText
		set fileUrl to "https://api.github.com/repos/" & repoFullName & "/contents/" & packagePath & "?ref=" & defaultBranch
		try
			set packageJson to do shell script my apiCommand(githubToken, fileUrl, "application/vnd.github.raw+json")
			if packageJson contains "\"expo\"" then
				set appName to repoFullName
				try
					set nameCode to "ObjC.import('stdlib'); const p=JSON.parse($.getenv('PACKAGE_JSON')); p.name||$.getenv('FALLBACK')"
					set appName to do shell script "PACKAGE_JSON=" & quoted form of packageJson & " FALLBACK=" & quoted form of repoFullName & " /usr/bin/osascript -l JavaScript -e " & quoted form of nameCode
				end try
				set subPath to my parentPath(packagePath)
				return {appName, subPath}
			end if
		end try
	end repeat
	return false
end findExpoInRepo

on prepareRepository(repoFullName, repoPath, githubToken)
	set authValue to do shell script "printf %s " & quoted form of ("x-access-token:" & githubToken) & " | /usr/bin/base64"
	if my folderExists(repoPath) then
		set commandText to "cd " & quoted form of repoPath & " && git -c http.extraHeader=" & quoted form of ("Authorization: Basic " & authValue) & " pull --ff-only"
	else
		set commandText to "git -c http.extraHeader=" & quoted form of ("Authorization: Basic " & authValue) & " clone " & quoted form of ("https://github.com/" & repoFullName & ".git") & " " & quoted form of repoPath
	end if
	try
		do shell script "/bin/zsh -lc " & quoted form of commandText
		return true
	on error errorMessage
		display alert "最新版を準備できませんでした" message errorMessage
		return false
	end try
end prepareRepository

on launchExpo(appPath, deviceName, appLabel)
	set nodePath to my findCommand("node")
	set npmPath to my findCommand("npm")
	if nodePath is "" or npmPath is "" then
		display alert "Node.jsが見つかりません" message "Node.js / npm の場所を確認できませんでした。"
		return
	end if
	set nodeBin to do shell script "/usr/bin/dirname " & quoted form of nodePath
	set homePath to POSIX path of (path to home folder)
	set sdkRoot to homePath & "Library/Android/sdk"
	set shellPath to nodeBin & ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" & sdkRoot & "/platform-tools:" & sdkRoot & "/emulator"
	set envPrefix to "export PATH=" & quoted form of shellPath & "; export ANDROID_HOME=" & quoted form of sdkRoot & "; "
	
	if my folderExists(appPath & "/node_modules") is false then
		display notification "初回セットアップ中です" with title "アプリ画面確認"
		try
			do shell script "/bin/zsh -lc " & quoted form of (envPrefix & "cd " & quoted form of appPath & " && " & quoted form of npmPath & " install")
		on error errorMessage
			display alert "初回セットアップに失敗しました" message errorMessage
			return
		end try
	end if
	
	if deviceName is "iPhone" then
		display notification "iPhone Simulatorを起動しています" with title "アプリ画面確認"
		try
			do shell script "/usr/bin/open -a Simulator"
		end try
		set platformOption to "--ios"
	else
		display notification "Android Emulatorを起動しています" with title "アプリ画面確認"
		if my ensureAndroidEmulator(sdkRoot) is false then return
		set platformOption to "--android"
	end if
	
	set expoPath to appPath & "/node_modules/.bin/expo"
	if my fileExists(expoPath) is false then
		display alert "Expoが見つかりません"
		return
	end if
	set freePort to my findFreePort()
	do shell script "/bin/rm -f " & quoted form of launchLog
	set setupCommand to envPrefix & "cd " & quoted form of appPath & " && exec " & quoted form of expoPath & " start " & platformOption & " --port " & freePort
	try
		do shell script "nohup /bin/zsh -lc " & quoted form of setupCommand & " > " & quoted form of launchLog & " 2>&1 &"
		display notification appLabel & " を開いています" with title "アプリ画面確認"
	on error errorMessage
		display alert "Expoを起動できませんでした" message errorMessage
	end try
end launchExpo

on ensureAndroidEmulator(sdkRoot)
	set adbPath to sdkRoot & "/platform-tools/adb"
	set emulatorPath to sdkRoot & "/emulator/emulator"
	if my fileExists(adbPath) is false or my fileExists(emulatorPath) is false then
		display alert "Android Emulatorが見つかりません" message "Android StudioでAndroid Emulatorを作成してください。"
		return false
	end if
	try
		do shell script quoted form of adbPath & " devices | /usr/bin/grep -q '^emulator-'"
		return true
	end try
	try
		set avdName to do shell script quoted form of emulatorPath & " -list-avds | /usr/bin/head -n 1"
		if avdName is "" then
			display alert "Android端末がありません" message "Android StudioのDevice Managerで仮想端末を1台作成してください。"
			return false
		end if
		do shell script "nohup " & quoted form of emulatorPath & " -avd " & quoted form of avdName & " > /tmp/app-screen-check-android.log 2>&1 &"
	on error errorMessage
		display alert "Android Emulatorを起動できませんでした" message errorMessage
		return false
	end try
	
	repeat with i from 1 to 45
		delay 2
		try
			set booted to do shell script quoted form of adbPath & " shell getprop sys.boot_completed 2>/dev/null"
			if booted is "1" then return true
		end try
		if i is 8 then display notification "Androidを起動中です" with title "アプリ画面確認"
		if i is 20 then display notification "Androidの起動完了を待っています" with title "アプリ画面確認"
	end repeat
	display alert "Androidの起動に時間がかかっています" message "Emulatorのホーム画面が表示されたら、もう一度Androidを選んでください。"
	return false
end ensureAndroidEmulator

on findCommand(commandName)
	try
		set resultPath to do shell script "/bin/zsh -lic " & quoted form of ("command -v " & commandName & " 2>/dev/null")
		if resultPath contains return then set resultPath to paragraph -1 of resultPath
		return resultPath
	on error
		return ""
	end try
end findCommand

on findFreePort()
	try
		set foundPort to do shell script "/bin/zsh -lc " & quoted form of "for p in {8081..8090}; do if ! /usr/sbin/lsof -iTCP:$p -sTCP:LISTEN -t >/dev/null 2>&1; then echo $p; break; fi; done"
		if foundPort is not "" then return foundPort
	end try
	return "8081"
end findFreePort

on parentPath(filePath)
	if filePath does not contain "/" then return ""
	set oldTID to AppleScript's text item delimiters
	set AppleScript's text item delimiters to "/"
	set parts to text items of filePath
	set AppleScript's text item delimiters to oldTID
	set parentParts to items 1 thru -2 of parts
	set AppleScript's text item delimiters to "/"
	set resultPath to parentParts as text
	set AppleScript's text item delimiters to oldTID
	return resultPath
end parentPath

on apiCommand(githubToken, apiUrl, acceptHeader)
	return "/usr/bin/curl -sS --fail -H " & quoted form of ("Authorization: Bearer " & githubToken) & " -H " & quoted form of ("Accept: " & acceptHeader) & " -H " & quoted form of "X-GitHub-Api-Version: 2022-11-28" & " " & quoted form of apiUrl
end apiCommand

on folderExists(folderPath)
	try
		do shell script "test -d " & quoted form of folderPath
		return true
	on error
		return false
	end try
end folderExists

on fileExists(filePath)
	try
		do shell script "test -f " & quoted form of filePath
		return true
	on error
		return false
	end try
end fileExists

on ensureFolder(folderPath)
	do shell script "mkdir -p " & quoted form of folderPath
end ensureFolder

on indexOf(targetValue, sourceList)
	repeat with i from 1 to count of sourceList
		if item i of sourceList is targetValue then return i
	end repeat
	return 1
end indexOf