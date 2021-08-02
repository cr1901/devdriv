hello.sys: hello.asm
	nasm -f bin hello.asm -o hello.sys -l hello.lst

clean:
	rm *.sys *.lst
