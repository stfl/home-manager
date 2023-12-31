# Moves the existing profile from /nix or $XDG_STATE_HOME/home-manager to
# $XDG_STATE_HOME/nix to match changed behavior in Nix 2.14. See
# https://github.com/NixOS/nix/pull/5226.
function migrateProfile() {
    declare -r stateHome="${XDG_STATE_HOME:-$HOME/.local/state}"
    declare -r userNixStateDir="$stateHome/nix"
    declare -r hmStateDir="$stateHome/home-manager"

    declare -r globalNixStateDir="${NIX_STATE_DIR:-/nix/var/nix}"
    declare -r globalProfilesDir="$globalNixStateDir/profiles/per-user/$USER"

    if [[ -e $globalProfilesDir/home-manager ]]; then
        declare -r oldProfilesDir="$globalProfilesDir"
    elif [[ -e $hmStateDir/profiles/home-manager ]]; then
        declare -r oldProfilesDir="$hmStateDir/profiles"
    fi

    declare -r newProfilesDir="$userNixStateDir/profiles"

    if [[ -v oldProfilesDir && -e $newProfilesDir ]]; then
        if [[ ! -e $newProfilesDir/home-manager ]]; then
            _i 'Migrating profile from %s to %s' "$oldProfilesDir" "$newProfilesDir"
            for p in "$oldProfilesDir"/home-manager-*; do
                declare name="${p##*/}"
                nix-store --realise "$p" --add-root "$newProfilesDir/$name" > /dev/null
            done
            cp -P "$oldProfilesDir/home-manager" "$newProfilesDir"
        fi

        rm "$oldProfilesDir/home-manager" "$oldProfilesDir"/home-manager-*
    fi
}

function setupVars() {
    declare -r stateHome="${XDG_STATE_HOME:-$HOME/.local/state}"
    declare -r userNixStateDir="$stateHome/nix"
    declare -r hmGcrootsDir="$stateHome/home-manager/gcroots"

    declare -r globalNixStateDir="${NIX_STATE_DIR:-/nix/var/nix}"
    declare -r globalProfilesDir="$globalNixStateDir/profiles/per-user/$USER"
    declare -r globalGcrootsDir="$globalNixStateDir/gcroots/per-user/$USER"

    # If the user Nix profiles path exists, then place the HM profile there.
    # Otherwise, if the global Nix per-user state directory exists then use
    # that. If neither exists, then we give up.
    #
    # shellcheck disable=2174
    if [[ -d $userNixStateDir/profiles ]]; then
        declare -r profilesDir="$userNixStateDir/profiles"
    elif [[ -d $globalProfilesDir ]]; then
        declare -r profilesDir="$globalProfilesDir"
    else
        _iError 'Could not find suitable profile directory, tried %s and %s' \
                "$userNixStateDir/profiles" "$globalProfilesDir" >&2
        exit 1
    fi

    declare -gr genProfilePath="$profilesDir/home-manager"
    declare -gr newGenPath="@GENERATION_DIR@";
    declare -gr newGenGcPath="$hmGcrootsDir/new-home"
    declare -gr currentGenGcPath="$hmGcrootsDir/current-home"
    declare -gr legacyGenGcPath="$globalGcrootsDir/current-home"

    if [[ -e $currentGenGcPath ]] ; then
        declare -g oldGenPath
        oldGenPath="$(readlink -e "$currentGenGcPath")"
    fi
}

function checkUsername() {
  local expectedUser="$1"

  if [[ "$USER" != "$expectedUser" ]]; then
    _iError 'Error: USER is set to "%s" but we expect "%s"' "$USER" "$expectedUser"
    exit 1
  fi
}

function checkHomeDirectory() {
  local expectedHome="$1"

  if ! [[ $HOME -ef $expectedHome ]]; then
    _iError 'Error: HOME is set to "%s" but we expect "%s"' "$HOME" "$expectedHome"
    exit 1
  fi
}

if [[ -v VERBOSE ]]; then
    export VERBOSE_ECHO=echo
    export VERBOSE_ARG="--verbose"
    export VERBOSE_RUN=""
else
    export VERBOSE_ECHO=true
    export VERBOSE_ARG=""
    export VERBOSE_RUN=true
fi

_i "Starting Home Manager activation"

# Verify that we can connect to the Nix store and/or daemon. This will
# also create the necessary directories in profiles and gcroots.
$VERBOSE_RUN _i "Sanity checking Nix"
nix-build --expr '{}' --no-out-link

# Also make sure that the Nix profiles path is created.
nix-env -q > /dev/null 2>&1 || true

migrateProfile
setupVars

if [[ -v DRY_RUN ]] ; then
    _i "This is a dry run"
    export DRY_RUN_CMD=echo
    export DRY_RUN_NULL="/dev/stdout"

    function dryRun() {
      echo "$@"
    }

    function dryRunNullOnReal() {
      echo "$@"
    }
else
    $VERBOSE_RUN _i "This is a live run"
    export DRY_RUN_CMD=""
    export DRY_RUN_NULL="/dev/null"

    function dryRun() {
      "$@"
    }

    function dryRunNullOnReal() {
      "$@" > /dev/null 2>&1
    }
fi

if [[ -v VERBOSE ]]; then
    _i 'Using Nix version: %s' "$(nix-env --version)"
fi

$VERBOSE_RUN _i "Activation variables:"
if [[ -v oldGenPath ]] ; then
    $VERBOSE_ECHO "  oldGenPath=$oldGenPath"
else
    $VERBOSE_ECHO "  oldGenPath undefined (first run?)"
fi
$VERBOSE_ECHO "  newGenPath=$newGenPath"
$VERBOSE_ECHO "  genProfilePath=$genProfilePath"
$VERBOSE_ECHO "  newGenGcPath=$newGenGcPath"
$VERBOSE_ECHO "  currentGenGcPath=$currentGenGcPath"
$VERBOSE_ECHO "  legacyGenGcPath=$legacyGenGcPath"
