#! /usr/bin/env bash

if [ ! -d Client.xcodeproj ]; then
    echo "Please run this from the project root that contains Client.xcodeproj"
    exit 1
fi

ignore_errors=false
# Check command line parameters
while [[ $# -gt 0 ]]
do
    case $1 in
        --ignore-errors)
            ignore_errors=true
        ;;
    esac
    shift
done

SDK_PATH=`xcrun --show-sdk-path`

# If the virtualenv with the Python modules that we need doesn't exist,
# or a clean run was requested, create the virtualenv.
if [ ! -d import-locales-env ] || [ "${clean_run}" = true ]
then
    rm -rf import-locales-env || exit 1
    echo "Setting up new virtualenv..."
    virtualenv import-locales-env --python=python3 || exit 1
    source import-locales-env/bin/activate || exit 1
    # install libxml2
    CFLAGS=-I"$SDK_PATH/usr/include/libxml2" LIBXML2_VERSION=2.9.2 pip install lxml==4.1.1 || exit 1
else
    echo "Reusing existing virtualenv found in import-locales-env"
    source import-locales-env/bin/activate || exit 1
fi

echo "Creating firefoxios-l10n Git repo"
rm -rf firefoxios-l10n 
git clone --depth 1 https://github.com/Qwant/firefoxios-l10n -b qwant-main firefoxios-l10n || exit 1

# Store current relative path to the script
script_path=$(dirname "$0")

# Remove the templates directory so that scripts do not have to special case it
rm -rf firefoxios-l10n/templates

if [ "$1" == "--release" ]
then
    # Get the list of shipping locales. File is in the root of the main
    # firefox-ios code repository
    shipping_locales=$(cat shipping_locales.txt)

    # Get the list of folders within the Git l10n clone and remove those
    # not available in shipping locales.
    for folder in firefoxios-l10n/*/
    do
        shipping_locale=false
        for locale in ${shipping_locales}
        do
            if [[ "firefoxios-l10n/${locale}/" == ${folder} ]]
            then
                # This is a shipping locale, I can stop searching
                shipping_locale=true
                break
            fi
        done

        if ! ${shipping_locale}
        then
            # Locale is not in shipping_locales.txt
            echo "Removing non shipping locale: ${folder}"
            rm -rf "${folder}"
        fi
    done
fi

# Clean up files (remove unwanted sections, map locale codes)
${script_path}/update-xliff.py firefoxios-l10n firefox-ios.xliff || exit 1

# Remove unwanted sections like Info.plist files and $(VARIABLES)
${script_path}/xliff-cleanup.py firefoxios-l10n/*/*.xliff || exit 1

# Export XLIFF files to individual .strings files
rm -rf localized-strings || exit 1
mkdir localized-strings || exit 1
if [ "${ignore_errors}" = true ]
then
    ${script_path}/xliff-to-strings.py firefoxios-l10n localized-strings --ignore-errors || exit 1
else
    ${script_path}/xliff-to-strings.py firefoxios-l10n localized-strings || exit 1
fi

# Update: We have to disable this for v29 and above as we need to add multiple Target Membership to Today.strings but unfortunately that is not supported by mod_pbxproj in strings-import script.
# Modify the Xcode project to reference the strings files we just created
# ${script_path}/strings-import.py Client.xcodeproj localized-strings || exit 1
