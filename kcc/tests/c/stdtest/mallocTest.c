void *malloc(unsigned int size);
void free(void *p);

int main() {
    void *p1 = malloc(100); // 10000008
    void *p2 = malloc(200); // 10000074
    void *p3 = malloc(100); // 10000144
    free(p2);
    void *p4 = malloc(50); // 10000074
    void *p5 = malloc(50); // 100000B0
    free(p3);
    free(p1);
    free(p4);
    free(p5);
    void *p6 = malloc(400); // 10000008
    free(p6);
}