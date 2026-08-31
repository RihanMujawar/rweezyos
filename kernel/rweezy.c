// SPDX-License-Identifier: GPL-2.0
/*
 * Rweezy OS -- kernel identity interface.
 *
 * Exposes a read-only /proc/rweezy entry carrying the operating system
 * identity, the running kernel version, the Rweezy ABI version and the
 * kernel build string.
 */

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/utsname.h>
#include <linux/version.h>

#define RWEEZY_ABI_VERSION 1

static int rweezy_show(struct seq_file *m, void *v)
{
	seq_printf(m, "Rweezy OS\n");
	seq_printf(m, "Kernel: %s\n", init_utsname()->release);
	seq_printf(m, "Rweezy ABI: %d\n", RWEEZY_ABI_VERSION);
	seq_printf(m, "Build: %s %s\n", init_utsname()->version,
		   init_utsname()->machine);
	return 0;
}

static int rweezy_open(struct inode *inode, struct file *file)
{
	return single_open(file, rweezy_show, NULL);
}

static const struct proc_ops rweezy_proc_ops = {
	.proc_open	= rweezy_open,
	.proc_read	= seq_read,
	.proc_lseek	= seq_lseek,
	.proc_release	= single_release,
};

static int __init rweezy_init(void)
{
	proc_create("rweezy", 0444, NULL, &rweezy_proc_ops);
	return 0;
}

module_init(rweezy_init);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Rweezy OS kernel identity interface");
MODULE_AUTHOR("Rehan Mujawar");
