" Indent with 4 spaces instead of tabs
set tabstop=4       " tab character displays as 4 columns
set shiftwidth=4    " >> << and auto-indent use 4 columns
set softtabstop=4   " Tab/Backspace move by 4 columns
set expandtab       " Tab key inserts spaces
autocmd FileType make setlocal noexpandtab   " Makefiles require real tabs
