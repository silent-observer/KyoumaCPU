struct vec3 {
    int x;
    int y;
    int z;
};

int main() {
    struct s {
        int x;
        int y;
    } a;
    struct s b;
    struct vec3 c;
    struct vec3 d;
    a.x = 1;
    a.y = a.x + 2;
    b.x = a.y + 3;
    b.y = b.x;
    c.z = a.x + a.y;
    c.x = 10;
    c.y = c.z + c.x;
    return c.y;
}