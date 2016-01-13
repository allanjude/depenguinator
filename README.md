depenguinator
=============

Use depenguinator 3.x to overwrite a remote linux server with a FreeBSD installer


Based on Colin Percival's "The Depenguinator 2.0"

Updated to support 9.x and later installer and dist file layout

Basic Method
============

 1. swapoff
 1. dd mfsbsd into the swap partition
 1. fiddle with grub to boot from the swap partition
 1. from inside mfsbsd, via ssh, you can reformat to FreeBSD

##Warning:
Still contains sharp edges, is not really for automated use. It is very likely that using this tool without understanding it will leave your server in an unbootable state.
