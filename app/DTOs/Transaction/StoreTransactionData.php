<?php

namespace App\DTOs\Transaction;

use App\Enums\RecurringFrequency;
use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\Rule;
use Spatie\LaravelData\Attributes\Validation\Date;
use Spatie\LaravelData\Attributes\Validation\In;
use Spatie\LaravelData\Attributes\Validation\Max;
use Spatie\LaravelData\Attributes\Validation\Min;
use Spatie\LaravelData\Attributes\Validation\RequiredIf;
use Spatie\LaravelData\Data;

class StoreTransactionData extends Data
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

        public bool $is_installment = false,

        #[RequiredIf('is_installment', true), Min(2), Max(360)]
        public ?int $installments_count = null,

        /** Número da primeira parcela a lançar (ex.: 15 num parcelamento já na 15/24). */
        #[Min(1), Max(360)]
        public int $installment_start = 1,

        /** 'total' = valor informado é o total; 'installment' = é o valor de cada parcela. */
        #[In(['total', 'installment'])]
        public string $amount_mode = 'total',

        /** Divisão com contatos (null = sem divisão). */
        public ?SplitData $split = null,

        /** Débito automático (parcelado/recorrente): no vencimento já marca como pago. */
        public bool $auto_pay = false,

        public bool $is_recurring = false,

        #[RequiredIf('is_recurring', true)]
        public ?RecurringFrequency $frequency = null,

        /** Tags livres (ex.: "iFood"). Criadas na hora se não existirem. @var list<string> */
        public array $tags = [],
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
            'tags' => ['array', 'max:10'],
            'tags.*' => ['string', 'max:40'],
        ];
    }
}
