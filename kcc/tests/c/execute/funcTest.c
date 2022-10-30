int f(int x) {
    int y = x + 2;
    return x + y;
}

int main() {
    int b = 1;
    int a = f(b + 1);
    return a;
}