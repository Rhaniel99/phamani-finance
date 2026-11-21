/** Tag livre de transação (ex.: "iFood", "Amazon"). Pessoal de cada usuário. */
export interface Tag {
    id: string;
    name: string;
    /** Só na lista de "Gerenciar tags". */
    transactions_count?: number;
}
