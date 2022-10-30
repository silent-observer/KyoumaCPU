struct mem_block {
    unsigned int size; // Highest bit is set to 1 if currently used, to 0 if not
    struct mem_block *next;
};

void *brk = (void*) 0x10000000;
struct mem_block *start_block = (struct mem_block *) 0;
struct mem_block *last_block = (struct mem_block *) 0;

void *malloc(unsigned int size) {
    struct mem_block *mem = start_block;
    int real_size = (size + 3) & ~3;
    while (mem) {
        if ((mem->size >> 31 != 0) || (size > mem->size)) {
            mem = mem->next;
        } else {
            if (real_size > mem->size - 8) {
                mem->size |= 1 << 31;
                return (void*)mem + 8;
            } else {
                unsigned required_size = real_size + 8;
                struct mem_block *new_block = (struct mem_block *)((void*)mem + required_size);
                new_block->size = mem->size - required_size;
                new_block->next = mem->next;
                mem->size = real_size | (1 << 31);
                mem->next = new_block;
                return (void*)mem + 8;
            }
        }
    }
    struct mem_block *new_block = brk;
    new_block->next = (struct mem_block *) 0;
    new_block->size = real_size | (1 << 31);
    brk += real_size + 8;
    if (!last_block) {
        last_block = start_block = new_block;
    } else {
        last_block->next = new_block;
        last_block = new_block;
    }
    return (void*)new_block + 8;
}

void merge_blocks() {
    struct mem_block *mem = start_block;
    while (mem && mem->next) {
        while (!(mem->size >> 31) && !(mem->next->size >> 31)) {
            mem->size += mem->next->size + 8;
            mem->next = mem->next->next;
            if (!mem->next) {
                brk = mem;

                mem = start_block;
                if (mem == brk) {
                    start_block = last_block = (struct mem_block *) 0;
                } else {
                    while (mem->next != brk)
                        mem = mem->next;
                    last_block = mem;
                    mem->next = (struct mem_block *) 0;
                }
                return;
            }
        }
        mem = mem->next;
    }
}

void free(void *p) {
    struct mem_block *mem = p - 8;
    mem->size &= ~(1 << 31);
    merge_blocks();
}