-- アプリ画面確認 v6
-- GitHub CLI不要版
-- GitHub APIから直接リポジトリを取得し、Expoアプリを探索します。
-- 起動中の状態を通知し、iPhone / Androidの起動失敗を明示します。

property appVersion : "v6"
property appsRoot : (POSIX path of (path to home folder)) & "Library/Application Support/アプリ画面確認/アプリ"
property keychainService : "アプリ画面確認-GitHub"
property keychainAccount : "github-token"
property launchLog : "/tmp/app-screen-check.log"

on run
	set githubToken to my getGitHubToken()
	if githubToken is "" then return
	
	my ensureFolder(appsRoot)
	display notification "GitHubからアプリを探しています" with title "アプリ画面確認"
	
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
	set repoPath to appsRoot & "/" & repoName
	
	set deviceChoice to choose from list {"iPhone", "Android"} with title "アプリ画面確認" with prompt "どちらで確認しますか？" OK button name "開く" cancel button name "キャンセル"
	if deviceChoice is false then return
	
	set deviceName to item 1 of deviceChoice
	
	display notification "1/4  GitHubの最新版を準備しています" with title "アプリ画面確認"
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
	
	set tokenDialog to display dialog "GitHubの読み取り用トークンを入力してください。" & return & return & "入力内容はmacOSのキーチェーンに保存され、次回から入力不要です。" default answer "" with title "アプリ画面確認" buttons {"キャンセル", "保存"} default button "保存" with hidden answer
	
	if button returned of tokenDialog is not "保存" then return ""
	set githubToken to text returned of tokenDialog
	
	if githubToken is "" then
		display alert "トークンが空です"
		return ""
	end if
	
	if my tokenWorks(githubToken) is false then
		display alert "GitHubに接続できませんでした" message "トークンが正しいか確認してください。"
		return ""
	end if
	
	try
		do shell script "security add-generic-password -U -s " & quoted form of keychainService & " -a " & quoted form of keychainAccount & " -w " & quoted form of githubToken
	on error errorMessage
		display alert "キーチェーンに保存できませんでした" message errorMessage
		return ""
	end try
	
	return githubToken
end getGitHubToken

on tokenWorks(githubToken)
	try
		set resultText to do shell script my apiCommand(githubToken, "https://api.github.com/user", "application/vnd.github+json")
		return resultText contains "\"login\""
	on error
		return false
	end try
end tokenWorks

on findExpoRepositories(githubToken)
	set reposUrl to "https://api.github.com/user/repos?per_page=100&sort=updated&affiliation=owner"
	
	try
		set reposJson to do shell script my apiCommand(githubToken, reposUrl, "application/vnd.github+json")
	on error errorMessage
		display alert "GitHubから取得できませんでした" message errorMessage
		return {}
	end try
	
	set repoLines to my parseRepos(reposJson)
	if (count of repoLines) is 0 then return {}
	
	set results to {}
	repeat with repoLine in repoLines
		set oldTID to AppleScript's text item delimiters
		set AppleScript's text item delimiters to tab
		set parts to text items of repoLine
		set AppleScript's text item delimiters to oldTID
		
		if (count of parts) ≥ 3 then
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

on parseRepos(reposJson)
	set jsCode to "ObjC.import('stdlib'); const r=JSON.parse($.getenv('REPOS_JSON')); r.filter(x=>!x.archived).map(x=>[x.name,x.full_name,x.default_branch].join('\\t')).join('\\n')"
	try
		set parsed to do shell script "REPOS_JSON=" & quoted form of reposJson & " /usr/bin/osascript -l JavaScript -e " & quoted form of jsCode
		if parsed is "" then return {}
		return paragraphs of parsed
	on error
		return {}
	end try
end parseRepos

on findExpoInRepo(githubToken, repoFullName, defaultBranch)
	set treeUrl to "https://api.github.com/repos/" & repoFullName & "/git/trees/" & defaultBranch & "?recursive=1"
	
	try
		set treeJson to do shell script my apiCommand(githubToken, treeUrl, "application/vnd.github+json")
	on error
		return false
	end try
	
	set packagePaths to my parsePackagePaths(treeJson)
	if (count of packagePaths) is 0 then return false
	
	repeat with packagePath in packagePaths
		set packageText to my fetchRawFile(githubToken, repoFullName, defaultBranch, packagePath)
		if packageText contains "\"expo\"" then
			set appName to my readPackageName(packageText, repoFullName)
			set subPath to my parentPath(packagePath)
			return {appName, subPath}
		end if
	end repeat
	
	return false
end findExpoInRepo

on parsePackagePaths(treeJson)
	set jsCode to "ObjC.import('stdlib'); const t=(JSON.parse($.getenv('TREE_JSON')).tree||[]); t.filter(x=>x.type==='blob' && x.path.endsWith('package.json') && x.path.split('/').length<=3).map(x=>x.path).join('\\n')"
	try
		set parsed to do shell script "TREE_JSON=" & quoted form of treeJson & " /usr/bin/osascript -l JavaScript -e " & quoted form of jsCode
		if parsed is "" then return {}
		return paragraphs of parsed
	on error
		return {}
	end try
end parsePackagePaths

on fetchRawFile(githubToken, repoFullName, defaultBranch, filePath)
	set fileUrl to "https://api.github.com/repos/" & repoFullName & "/contents/" & filePath & "?ref=" & defaultBranch
	try
		return do shell script my apiCommand(githubToken, fileUrl, "application/vnd.github.raw+json")
	on error
		return ""
	end try
end fetchRawFile

on readPackageName(packageText, fallbackName)
	set jsCode to "ObjC.import('stdlib'); const p=JSON.parse($.getenv('PACKAGE_JSON')); p.name || $.getenv('FALLBACK_NAME')"
	try
		return do shell script "PACKAGE_JSON=" & quoted form of packageText & " FALLBACK_NAME=" & quoted form of fallbackName & " /usr/bin/osascript -l JavaScript -e " & quoted form of jsCode
	on error
		return fallbackName
	end try
end readPackageName

on parentPath(filePath)
	if filePath does not contain "/" then return ""
	
	set oldTID to AppleScript's text item delimiters
	set AppleScript's text item delimiters to "/"
	set parts to text items of filePath
	set AppleScript's text item delimiters to oldTID
	
	if (count of parts) ≤ 1 then return ""
	set parentParts to items 1 thru -2 of parts
	
	set AppleScript's text item delimiters to "/"
	set resultPath to parentParts as text
	set AppleScript's text item delimiters to oldTID
	
	return resultPath
end parentPath

on prepareRepository(repoFullName, repoPath, githubToken)
	set authValue to my gitBasicAuth(githubToken)
	
	if my folderExists(repoPath) then
		set updateCommand to "cd " & quoted form of repoPath & " && git -c http.extraHeader=" & quoted form of ("Authorization: Basic " & authValue) & " pull --ff-only"
		try
			do shell script "/bin/zsh -lc " & quoted form of updateCommand
			return true
		on error errorMessage
			display alert "最新版に更新できませんでした" message "ローカル側に変更がある可能性があります。" & return & return & errorMessage
			return false
		end try
	else
		set cloneUrl to "https://github.com/" & repoFullName & ".git"
		set cloneCommand to "git -c http.extraHeader=" & quoted form of ("Authorization: Basic " & authValue) & " clone " & quoted form of cloneUrl & " " & quoted form of repoPath
		try
			do shell script "/bin/zsh -lc " & quoted form of cloneCommand
			return true
		on error errorMessage
			display alert "リポジトリを取得できませんでした" message errorMessage
			return false
		end try
	end if
end prepareRepository

on gitBasicAuth(githubToken)
	return do shell script "printf %s " & quoted form of ("x-access-token:" & githubToken) & " | /usr/bin/base64"
end gitBasicAuth

on launchExpo(appPath, deviceName, appLabel)
	do shell script "/bin/rm -f " & quoted form of launchLog
	
	if deviceName is "iPhone" then
		display notification "2/4  iPhone Simulatorを起動しています" with title "アプリ画面確認"
		if my prepareIOS() is false then return
		set platformOption to "--ios"
		set openingText to "Opening on iOS"
	else
		display notification "2/4  Android Emulatorを起動しています" with title "アプリ画面確認"
		if my prepareAndroid() is false then return
		set platformOption to "--android"
		set openingText to "Opening on Android"
	end if
	
	if my folderExists(appPath & "/node_modules") is false then
		display notification "3/4  初回セットアップ中です。少し時間がかかります" with title "アプリ画面確認"
	else
		display notification "3/4  Expoを起動しています" with title "アプリ画面確認"
	end if
	
	set envPrefix to "export PATH=\"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.volta/bin:$HOME/.npm-global/bin:$HOME/Library/Android/sdk/platform-tools:$HOME/Library/Android/sdk/emulator:$PATH\"; "
	set setupCommand to envPrefix & "cd " & quoted form of appPath & " && if [ ! -d node_modules ]; then npm install; fi && exec npx expo start " & platformOption
	set wrappedCommand to "/bin/zsh -lc " & quoted form of setupCommand
	
	try
		set expoPid to do shell script "nohup " & wrappedCommand & " > " & quoted form of launchLog & " 2>&1 & echo $!"
	on error errorMessage
		display alert "Expoを起動できませんでした" message errorMessage
		return
	end try
	
	if expoPid is "" then
		display alert "Expoを起動できませんでした" message "起動処理を開始できませんでした。"
		return
	end if
	
	display notification "4/4  " & deviceName & "への接続を待っています" with title "アプリ画面確認"
	
	repeat with attempt from 1 to 18
		delay 5
		
		if my logContains(openingText) then
			display alert "起動処理は正常に進んでいます" message appLabel & " を " & deviceName & " で開いています。" & return & return & "初回はアプリが表示されるまで1〜2分かかる場合があります。"
			return
		end if
		
		if my logHasFailure() then
			set logTail to my lastLogLines()
			display alert "起動に失敗しました" message logTail
			return
		end if
		
		if my processIsRunning(expoPid) is false then
			set logTail to my lastLogLines()
			display alert "起動処理が停止しました" message logTail
			return
		end if
		
		if attempt is 3 then
			display notification "まだ処理中です。正常に待機しています" with title "アプリ画面確認"
		else if attempt is 6 then
			display notification "まだ処理中です。初回起動は時間がかかる場合があります" with title "アプリ画面確認"
		else if attempt is 12 then
			display notification "Expoは動作中です。引き続き接続を待っています" with title "アプリ画面確認"
		end if
	end repeat
	
	if my processIsRunning(expoPid) then
		display alert "処理は継続中です" message "Expoは停止していませんが、90秒以内に端末への接続完了を確認できませんでした。" & return & return & deviceName & "の画面を確認してください。"
	else
		display alert "起動処理が停止しました" message my lastLogLines()
	end if
end launchExpo

on prepareIOS()
	try
		do shell script "/usr/bin/open -a Simulator"
	on error errorMessage
		display alert "iPhone Simulatorを起動できませんでした" message errorMessage
		return false
	end try
	
	repeat with attempt from 1 to 12
		delay 3
		try
			do shell script "/usr/bin/xcrun simctl list devices booted | /usr/bin/grep -q '(Booted)'"
			return true
		end try
		if attempt is 5 then display notification "iPhone Simulatorの起動を待っています" with title "アプリ画面確認"
	end repeat
	
	display alert "iPhone Simulatorの起動に時間がかかっています" message "Simulatorは開きましたが、起動完了を確認できませんでした。Simulatorの画面を確認してください。"
	return false
end prepareIOS

on prepareAndroid()
	set emulatorPath to my findAndroidTool("emulator")
	set adbPath to my findAndroidTool("adb")
	
	if emulatorPath is "" or adbPath is "" then
		display alert "Android Emulatorを起動できませんでした" message "Android SDKの emulator または adb が見つかりません。Android Studioの設定を確認してください。"
		return false
	end if
	
	set runningDevice to false
	try
		do shell script quoted form of adbPath & " devices | /usr/bin/grep -q '^emulator-'"
		set runningDevice to true
	end try
	
	if runningDevice is false then
		try
			set avdName to do shell script quoted form of emulatorPath & " -list-avds | /usr/bin/head -n 1"
		on error
			set avdName to ""
		end try
		
		if avdName is "" then
			display alert "Android端末が見つかりません" message "Android StudioのDevice Managerで仮想端末を1つ作成してください。"
			return false
		end if
		
		try
			do shell script "nohup " & quoted form of emulatorPath & " -avd " & quoted form of avdName & " > /tmp/app-screen-check-android.log 2>&1 &"
		on error errorMessage
			display alert "Android Emulatorを起動できませんでした" message errorMessage
			return false
		end try
	end if
	
	repeat with attempt from 1 to 30
		delay 3
		try
			set bootState to do shell script quoted form of adbPath & " shell getprop sys.boot_completed 2>/dev/null | /usr/bin/tr -d '\\r'"
			if bootState is "1" then return true
		end try
		
		if attempt is 5 then
			display notification "Android Emulatorの起動を待っています" with title "アプリ画面確認"
		else if attempt is 15 then
			display notification "Androidはまだ起動中です" with title "アプリ画面確認"
		end if
	end repeat
	
	display alert "Android Emulatorの起動に時間がかかっています" message "90秒以内にAndroidの起動完了を確認できませんでした。Emulatorの画面を確認してください。"
	return false
end prepareAndroid

on findAndroidTool(toolName)
	set candidates to {(POSIX path of (path to home folder)) & "Library/Android/sdk/platform-tools/" & toolName, (POSIX path of (path to home folder)) & "Library/Android/sdk/emulator/" & toolName}
	repeat with candidatePath in candidates
		try
			do shell script "test -x " & quoted form of candidatePath
			return candidatePath
		end try
	end repeat
	
	try
		return do shell script "/bin/zsh -lc " & quoted form of ("command -v " & toolName)
	on error
		return ""
	end try
end findAndroidTool

on processIsRunning(processId)
	try
		do shell script "/bin/kill -0 " & processId
		return true
	on error
		return false
	end try
end processIsRunning

on logContains(searchText)
	try
		do shell script "/usr/bin/grep -Fq " & quoted form of searchText & " " & quoted form of launchLog
		return true
	on error
		return false
	end try
end logContains

on logHasFailure()
	try
		do shell script "/usr/bin/grep -Eiq 'CommandError:|npm ERR!|Error: Cannot|Unable to|No Android connected device|No development build' " & quoted form of launchLog
		return true
	on error
		return false
	end try
end logHasFailure

on lastLogLines()
	try
		set logText to do shell script "/usr/bin/tail -n 12 " & quoted form of launchLog
		if logText is "" then return "詳しいエラー情報を取得できませんでした。"
		return logText
	on error
		return "詳しいエラー情報を取得できませんでした。"
	end try
end lastLogLines

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

on ensureFolder(folderPath)
	do shell script "mkdir -p " & quoted form of folderPath
end ensureFolder

on indexOf(targetValue, sourceList)
	repeat with i from 1 to count of sourceList
		if item i of sourceList is targetValue then return i
	end repeat
	return 1
end indexOf
