-- アプリ画面確認 v5
-- GitHub CLI不要版
-- GitHub APIから直接リポジトリを取得し、Expoアプリを探索します。
-- 初回のみGitHubトークンを入力し、macOSキーチェーンへ保存します。

property appVersion : "v5"
property appsRoot : (POSIX path of (path to home folder)) & "Library/Application Support/アプリ画面確認/アプリ"
property keychainService : "アプリ画面確認-GitHub"
property keychainAccount : "github-token"

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

	display notification selectedLabel & " を準備しています" with title "アプリ画面確認"

	if my prepareRepository(repoFullName, repoPath, githubToken) is false then return

	if expoSubPath is "" then
		set expoPath to repoPath
	else
		set expoPath to repoPath & "/" & expoSubPath
	end if

	if deviceName is "iPhone" then
		my launchExpo(expoPath, "--ios")
	else
		my launchExpo(expoPath, "--android")
	end if
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
	-- 自分がアクセスできるリポジトリを最大100件取得
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
	-- JXAでJSONをTSVへ変換
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
	-- リポジトリのツリーから深さ3以内のpackage.jsonを取得
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
	-- Contents APIをraw形式で取得。base64復号は不要。
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
	-- GitHub Git HTTPS認証用
	return do shell script "printf %s " & quoted form of ("x-access-token:" & githubToken) & " | /usr/bin/base64"
end gitBasicAuth

on launchExpo(appPath, platformOption)
	set setupCommand to "cd " & quoted form of appPath & " && if [ ! -d node_modules ]; then npm install; fi && npx expo start " & platformOption
	set wrappedCommand to "/bin/zsh -lc " & quoted form of setupCommand

	try
		do shell script "nohup " & wrappedCommand & " > /tmp/app-screen-check.log 2>&1 &"
		display notification "起動を開始しました" with title "アプリ画面確認"
	on error errorMessage
		display alert "起動できませんでした" message errorMessage
	end try
end launchExpo

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
