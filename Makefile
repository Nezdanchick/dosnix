name:=dosnix
arch:=x86_64

binary:=./binary
sources:=./sources
downloads:=./downloads
config:=./config

# latest linux kernel
kernel-url:=$(shell wget -q "http://kernel.org" -O - | grep 'tar.xz' | head -1 | cut -d "=" -f2 | sed -e 's/\"//g' | sed -e 's/>.*//g')
kernel-tar-filename:=$(shell echo $(kernel-url) | sed -e 's/https.*\///g')
kernel-tar-path:=$(downloads)/$(kernel-tar-filename)
kernel-src:=$(sources)/$(shell echo $(kernel-tar-filename) | sed -e 's/.tar.xz//g')
kernel-path:=$(kernel-src)/arch/$(arch)/boot/bzImage
kernel:=$(binary)/vmlinuz

# latest busybox
busybox-url:=$(shell wget -q "https://busybox.net/" -O - | grep 'tar.bz2' | head -1 | cut -d "=" -f2 | sed -e 's/\"//g' | sed -e 's/>.*//g')
busybox-tar-filename:=$(shell echo $(busybox-url) | sed -e 's/https.*\///g')
busybox-tar-path:=$(downloads)/$(busybox-tar-filename)
busybox-src:=$(sources)/$(shell echo $(busybox-tar-filename) | sed -e 's/.tar.bz2//g')
busybox-path:=$(busybox-src)/busybox_unstripped
busybox:=$(binary)/busybox

# initramfs
initramfs-dir:=$(binary)/initramfs
initramfs-bin:=$(initramfs-dir)/bin
initramfs-img:=$(binary)/initramfs.img

# iso
iso-img:=$(binary)/$(name).iso
iso-dir:=$(binary)/iso
dd-device:=/dev/sda

# commands
download:=wget -qc
extract:=tar -xf
runner:=qemu-system-$(arch)

# system values
cpu-cores:=$(shell nproc)

# targets
all: create-iso run

build:
	@echo "start building $(name)"
	
	@mkdir -p $(binary)
	@mkdir -p $(sources)
	@mkdir -p $(downloads)

	@echo "downloading kernel..."
	@$(download) $(kernel-url) -O $(kernel-tar-path)
	@echo "downloading busybox..."
	@$(download) $(busybox-url) -O $(busybox-tar-path)
	
	@echo "extracting kernel..."
	@[ -d $(kernel-src) ] || $(extract) $(kernel-tar-path) -C $(sources)
	@echo "extracting busybox..."
	@[ -d $(busybox-src) ] || $(extract) $(busybox-tar-path) -C $(sources)

	@echo "building kernel..."
	@[ -a $(kernel-path) ] && echo "kernel is already built" || \
		(make -C $(kernel-src) mrproper defconfig && make -j$(cpu-cores) -C $(kernel-src))
	
	@echo "building busybox..."
	@[ -a $(busybox-path) ] && echo "busybox is already built" || \
		(make -C $(busybox-src) defconfig && \
		sed -i "s|.*CONFIG_EXTRA_LDFLAGS.*|CONFIG_EXTRA_LDFLAGS=\"-static\"|" $(busybox-src)/.config && \
		make CC=musl-gcc -j$(cpu-cores) -C $(busybox-src))

	@cp $(kernel-path) $(kernel)
	@cp $(busybox-path) $(busybox)
	@echo "build success!"

create-initramfs: build
	@echo "creating initramfs..."
	@mkdir -p $(initramfs-dir)/{bin,dev,etc,proc,sys,usr}
	@cp $(config)/init $(initramfs-dir)/init
	@chmod 777 $(initramfs-dir)/init
	@cp $(busybox) $(initramfs-bin)/busybox

	@(cd $(initramfs-bin) && $(foreach app,$(shell $(busybox) --list),ln -fs /bin/busybox $(app);))
	
	@(cd $(initramfs-dir) && find . | cpio -R root:root -H newc -o | gzip > ../../$(initramfs-img))
	@echo "done!"

create-iso: build create-initramfs
	@echo "creating iso..."
	@mkdir -p $(iso-dir)/boot/grub
	@cp {,$(kernel),$(initramfs-img)} $(iso-dir)/boot/
	@cp $(config)/grub.cfg $(iso-dir)/boot/grub/
	
	@grub-mkrescue -o $(iso-img) $(iso-dir) \
	--product-name=$(name) \
	--compress="xz" \
	--fonts="unicode" \
	--fonts="unicode" \
	--locales="" \
	--themes="" \
	--install-modules="normal linux search all_video gfxterm font \
	part_acorn part_amiga part_apple part_bsd part_dfly \
	part_dvh part_gpt part_plan part_sun part_sunpc"
	part_dvh part_gpt part_plan part_sun part_sunpc"

run: create-iso
	@echo "running..."
	@$(runner) $(iso-img) &

dd: create-iso
	@echo "WARNING: be careful!"
	@echo "writing to $(dd-device)..."
	sudo dd if=$(iso-img) of=$(dd-device)

clean:
	@rm -rf $(binary) $(sources)

clean-all:
	@rm -rf $(binary) $(sources) $(downloads)

.PHONY: all build create-iso clean
