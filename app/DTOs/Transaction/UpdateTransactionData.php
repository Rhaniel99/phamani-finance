<?php

namespace App\DTOs\Transaction;

use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\Rule;
use Spatie\LaravelData\Attributes\Validation\Date;
use Spatie\LaravelData\Attributes\Validation\In;
use Spatie\LaravelData\Attributes\Validation\Max;
use Spatie\LaravelData\Attributes\Validation\Min;
use Spatie\LaravelData\Data;

/**
 * Edição de uma única transação (ou de uma parcela isolada).
 * Parcelamento e recorrência não são alterados por aqui.
 */
class UpdateTransactionData extends Data
{
    public function __construct(
        #[Max(255)]
        public string $description,

        #[Min(0.01)]
        public float $amount,

        #[In(['income', 'expense'])]
        public string $type,

        public string $category_id,

        /** Null quando outra pessoa pagou (divisão). */
        public ?string $account_id,

        #[Date]
        public string $date,

        /** Só para parcelas: repete o novo valor nas parcelas seguintes. */
        public bool $apply_to_following = false,

        /** Divisão com contatos (null = sem divisão). */
        public ?SplitData $split = null,

        /** Tags livres. Null = não mexe nas tags. @var list<string>|null */
        public ?array $tags = null,
    ) {}

    /**
     * Conta e categoria precisam pertencer ao usuário autenticado.
     *
     * @return array<string, array<int, mixed>>
     */
    public static function rules(): array
    {
        return [
            'category_id' => [
                'required', 'uuid',
                Rule::exists('categories', 'id')->where('user_id', Auth::id()),
            ],
            // Obrigatória, a não ser que outra pessoa tenha pago (divisão com "quem pagou").
            'account_id' => [
                Rule::requiredIf(fn () => ! filled(request()->input('split.paid_by_contact_id'))),
                'nullable', 'uuid',
                Rule::exists('accounts', 'id')->where('user_id', Auth::id()),
            ],
            'tags' => ['nullable', 'array', 'max:10'],
            'tags.*' => ['string', 'max:40'],
        ];
    }
}
