int sort(int *arr, int size) {
    for (int i = 1; i < size; i++) {
        int x = arr[i];
        int j = i - 1;
        for (;j >= 0 && arr[j] > x; j--)
            arr[j+1] = arr[j];
        arr[j+1] = x;
    }
    return 0;
}

int main() {
    int a[10] = {5, 6, 7, 10, 8, 9, 2, 4, 3, 1};
    sort(a, 10);
    for (int i = 1; i < 10; i++) {
        if (a[i] != i + 1) return i + 1;
    }
    return 0;
}