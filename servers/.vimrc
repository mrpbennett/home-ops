" --- Minimal but powerful server .vimrc ---

" space as leader
let mapleader=" "

" Enable syntax highlighting if available
if has("syntax")

syntax on
endif

" Line numbers
set number
set relativenumber

" Better backspace behavior
set backspace=indent,eol,start

" Searching
set hlsearch
set incsearch
set ignorecase
set smartcase

" Show matching brackets
set showmatch

" Allow recursive file searching with :find
set path+=**

" Enable mouse if available (nice for terminals)
set mouse=a

" Faster redraw
set lazyredraw

" Open Explorer with <leader>e
noremap <leader>e :Explore<CR>

