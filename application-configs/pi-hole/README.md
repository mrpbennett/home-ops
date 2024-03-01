# Setting up PiHole

https://discourse.pi-hole.net/t/update-what-to-do-if-port-53-is-already-in-use/52033

When the Port 53 is already in Use, you can check this with this command
(ubuntu):

Port 53 is being used at your host machine, that's why you can not bind 53 to
host.

To find what is using port 53 you can do: sudo lsof -i -P -n | grep LISTEN

I'm a 99.9% sure that systemd-resolved is what is listening to port 53.

To solve that you need to edit the `/etc/systemd/resolved.conf` and uncomment
DNSStubListener and change it to no, so it looks like this: DNSStubListener=no

After that reboot your system or restart the service with
`service systemd-resolved restart`
