# cftf

It's not pretty, but it's functional for everything except the cloudwatch monitor.

I would've used more modules, but every time I tried to break anything more than
the subnets out into a module, I started getting errors. 

Additionally, in order to get everything to build properly, the subnets need
to be built out first via `terraform apply -target=module.subnets`

This has truly shown me that I was climbing Mount Stupid (see
https://knowyourmeme.com/photos/2303426-dunning-kruger-effect for context) with
respect to Terraform. Thought I knew more than I did, but without the
templates I had built years ago, my skills atrophied.
