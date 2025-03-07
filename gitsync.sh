#!/bin/bash
# TODO: output doesn't make sense when run from terminal

# ----------------------------------------------
# Checking if everything is ready for syncing

# Did user provide a path?
if [[ -z "$1" ]]; then
	echo "provide a path to a git repo you wish to sync"
	exit 1
fi

echo "Script starting..."
echo "cd $1"

cd "$1" || exit 2

repo_dir="$(pwd)"
repo_name="$(basename "$repo_dir")"

# Is the specified dir a valid git repo?
echo -n "Checking if $repo_name is a valid git repo..."
if ! git rev-parse --is-inside-work-tree 1>/dev/null 2>/dev/null; then
	echo "$repo_dir is not a git repo!"
	exit 1
fi
echo "Confirmed."

notify="notify-send -t 2500 -a gitsync gitsync@$repo_name"
notification=""

# Is the remote currently reachable?
echo -n "Checking if the remote is reachable..."
if ! timeout 20s git ls-remote 1>/dev/null 2>/dev/null; then
	msg="Could not reach remote - aborting sync."
	echo "$msg"
	$notify "$msg"
	exit 2
fi
echo "Confirmed."

# ----------------------------------------------
# Check status, add and commit local changes
echo "---------------------------------------"
echo "Checking if there are uncommited changes..."
echo "git status --porcelain"
status=$(git status --porcelain)
echo "$status"
local_changes=false

if [[ -z "$status" ]]; then
	msg="No local changes to commit."
	echo "$msg"
	notification+="\n$msg"
else
	git add -A

	echo ""
	echo "Commiting local changes..."
	message="$(date +'%d-%m-%Y') $(hostname)"
	commit_output=$(git commit -m "$message")
	echo "$commit_output"

	msg="Local:\n$commit_output"
	notification+="\n$msg"

	local_changes=true
fi

# ----------------------------------------------
# Fetch
echo "---------------------------------------"
echo "Fetching from remote..."
git fetch
echo ""

# ----------------------------------------------
# Check if local is behind remote and merge if necessary

# outputs commits between our HEAD and remote
# so gives no output when they are equal
echo "Checking if remote has new stuff..."
if [[ -z "$(git log HEAD..origin/master --oneline)" ]]; then
	local_behind=false
else
	local_behind=true
fi

if [[ $local_behind == false ]]; then
	msg="Local branch up to date with origin."
	notification+="\n$msg"
	echo "$msg"
	echo ""
else
	echo -n "Local branch is behind remote, attempting fast-forward..."
	if pull_output=$(git pull --ff-only 2>&1); then
		# Fast-forward was successfull
		pull_diff="$(echo "$pull_output" | tail -n 1)"

		echo "success!"
		echo "$pull_output"

		msg="FF successful:\n$pull_diff"
		notification+="\n$msg"
	else
		# Conflict makes FF impossible, attempt automatic merge
		echo "failed!"
		echo -n "Attempting automatic merge..."
		merge_msg="$(date +'%d-%m-%Y') $(hostname) (automatic merge)"
		if ! merge_output=$(git merge -m "$merge_msg" 2>&1); then
			# Automerge failed, error out and exit *without pushing*
			notify-send -u critical -e "git@$repo_name" "Automatic merge failed! git merge output:\n$merge_output"
			echo "failed! Fix conflicts manually..."
			echo "$merge_output"
			exit 3
		fi
		echo "success!"
		echo "$merge_output"

		# Automatic merge was successful
		merge_diff="$(echo "$merge_output" | tail -n 1)"
		msg="Automatic merge successful\n$merge_diff"
		notification+="\n$msg"
	fi
fi

# ----------------------------------------------
# Check if local is ahead of remote and push if necessary

echo ""
echo "Checking if we have new stuff..."
if [[ -z "$(git log origin/master..HEAD --oneline)" ]]; then
	local_ahead=false
else
	local_ahead=true
fi

if [[ $local_ahead == true ]]; then
	echo -n "Local branch is ahead of remote, pushing changes..."
	if push_output=$(git push 2>&1); then
		echo "success!"
		echo "$push_output"
		msg="Pushed successfully\n$push_output"
		notification+="\n$msg"
	else
		echo "failed!"
		echo "$push_output"
		msg="Failed to push to remote!\n$push_output"
		notify-send -u critical -e "git@$repo_name" "Failed pushing to remote! output:\n$push_output"
		exit 2
	fi
else
	echo "Origin is up to date with the local branch."
fi

# ----------------------------------------------
# Display a notification if something changed
if [[ $local_ahead == true || $local_behind == true ]]; then
	echo ""
	echo "Stuff changed, displaying notification"
	$notify "$notification"
else
	echo ""
	echo "Nothing changed, no notification required"
fi

exit 0
