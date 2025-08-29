# generate-debian-preseed-iso

This Bash script generates Debian ISOs with preseed for multiple environments. With this script, you can automate the process of generating custom Debian images with preconfigured settings for various environments.

## Requirements

To use this script, you need to install the following packages:

    $ sudo apt install wget curl p7zip-full genisoimage syslinux-utils

## TODO
- help in bash
- add options
- move server variable to .env
- allow possibility to have a different preseed if not a server (VM for example) ?
- repair authorized_key (need to copy on ISO first)
    ```
    function add_static_to_cdrom() {
        progress "Adding ./static content to ISO /preseed..."

        local static
        static="./cdrom"
        install -d -m 755 "$isofiles/preseed"
        (
            cd "$static"
            find . -name \* -a ! \( -name \*~ -o -name \*.bak -o -name \*.orig \) -print0
        ) | cpio -v -p -L -0 -D "$static" "$isofiles/preseed"
        chmod -w -R "$isofiles/preseed"
    }
    ```
- change boot option on iso (menu grub)
- rework following https://github.com/lboulard/debian-preseed/blob/master/make-preseed-iso.sh
- dockerise?