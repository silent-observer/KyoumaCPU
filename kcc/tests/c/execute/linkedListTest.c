struct node {
    int data;
    struct node *next;
};

struct node arr[20];
int arrLen;
struct node *lastNode;

struct node *createNode() {
    return &arr[arrLen++];
}

void addNode(int data) {
    struct node *n = createNode();
    n->data = data;
    n->next = (struct node *)0;
    if (lastNode)
        lastNode->next = n;
    lastNode = n;
}

void insertNodeAfter(int data, struct node *n) {
    struct node *new = createNode();
    new->data = data;
    new->next = n->next;
    if (!n->next) {
        lastNode->next = new;
        lastNode = new;
    }
    n->next = new;
}

void removeNodeAfter(struct node *n) {
    struct node *p = n->next->next;
    if (!p)
        lastNode = n;
    n->next = p;
}

struct node *getNode(int i) {
    struct node *n = &arr[0];
    while (i != 0) {
        n = n->next;
        i--;
    }
    return n;
}

int main() {
    addNode(1);
    addNode(2);
    addNode(3);
    addNode(4);
    struct node *three = getNode(2);
    insertNodeAfter(10, three);
    struct node *one = getNode(0);
    removeNodeAfter(one);
    return getNode(3)->data;
}