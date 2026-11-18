export type User = {
    id: string;
    name: string;
    email: string;
    avatar: string | null;
};

export type Auth = {
    user: User | null;
};
