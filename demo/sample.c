/* Demo fixture for lspnav.nvim. The helpers call each other, so the symbol
 * tree, the references window, and the call hierarchy all have something to
 * show. No headers are needed, which keeps clangd quiet. */

static int is_space(char c)
{
    return c == ' ' || c == '\t' || c == '\n';
}

static char *skip_space(char *s)
{
    while (is_space(*s))
        s++;
    return s;
}

static char *trim_end(char *s)
{
    char *end = s;
    while (*end)
        end++;
    while (end > s && is_space(end[-1]))
        end--;
    *end = '\0';
    return s;
}

char *normalize(char *s)
{
    return trim_end(skip_space(s));
}

int greet(char *name)
{
    char *clean = normalize(name);
    int length = 0;
    while (clean[length])
        length++;
    return length;
}

int farewell(char *name)
{
    char *clean = normalize(name);
    int length = 0;
    while (clean[length])
        length++;
    return length;
}

int main(void)
{
    greet("  world  ");
    farewell("  world  ");
    return 0;
}
