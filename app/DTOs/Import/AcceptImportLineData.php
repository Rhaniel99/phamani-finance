<?php

namespace App\DTOs\Import;

use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\Rule;
use Spatie\LaravelData\Attributes\Validation\Date;
use Spatie\LaravelData\Attributes\Validation\In;
use Spatie\LaravelData\Attributes\Validation\Max;
use Spatie\LaravelData\Attributes\Validation\Min;
use Spatie\LaravelData\Data;

/**
 * Uma linha do extrato que vai virar compra (ou crédito) no cartão.
 *
 * split: null = só sua; "half" = metade com o contato (entra no acerto); "theirs" = compra para ele (a receber).
 */
class AcceptImportLineData extends Data
{
    public function __construct(
        #[Min(0)]
        public int $index,

        #[Max(255)]
        public string $name,

        #[Min(0.01)]
        public float $amount,

        #[In(['income', 'expense'])]
        public string $type,

        #[Date]
        public string $date,

        public string $category_id,

        /** @var list<string> */
        public array $tags = [],

        #[In(['half', 'theirs'])]
        public ?string $split = null,

        public ?string $split_contact_id = null,
    ) {}

    /**
     * @return array<string, array<int, mixed>>
     */
    public static function rules(): array
    {
        return [
            'category_id' => ['required', 'uuid', Rule::exists('categories', 'id')->where('user_id', Auth::id())],
            'tags' => ['array', 'max:10'],
            'tags.*' => ['string', 'max:40'],
            'split_contact_id' => [
                'nullable', 'uuid', 'required_with:split',
                Rule::exists('contacts', 'id')->where('user_id', Auth::id()),
            ],
        ];
    }
}
