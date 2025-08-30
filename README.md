# generate-debian-preseed-iso

This Bash script generates Debian ISOs with preseed for multiple environments. With this script, you can automate the process of generating custom Debian images with preconfigured settings for various environments.

## Requirements

To use this script, you need to install the following packages:

    $ sudo apt install wget curl p7zip-full genisoimage syslinux-utils

## Usage

```
Usage: debian-preseed-iso-generator.sh -n server_name -i ip_address/cidr -g gateway -d dns_ip

  -n server_name
      Name of the server to install
  -i ip_address/cidr
      IP address of the server to install on format ip/cidr (ex: 192.168.0.200/24)
  -g gateway
      network gateway
  -d dns_ip
      DNS Ip address
```

an ISO image file is generated into `ISOs/server_name`

## TODO
- allow possibility to have a different preseed if not a server (VM for example) ?
- dockerise?

## Note
Based on the projects
- https://github.com/bergmann-max/debian-preseed-iso-generator/
- https://github.com/lboulard/debian-preseed