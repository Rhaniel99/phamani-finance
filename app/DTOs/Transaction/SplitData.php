<?php

namespace App\DTOs\Transaction;

use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\Rule;
use Spatie\LaravelData\Attributes\DataCollectionOf;
use Spatie\LaravelData\Attributes\Validation\In;
use Spatie\LaravelData\Data;

/**
 * Divisão de uma despesa entre você e seus contatos.
 *
 * - mode "equal": partes iguais; "custom": valor de cada um (a soma tem que bater com o valor informado).
 * - paid_by_contact_id: quem pagou (null = você). Se foi outra pessoa, nenhuma conta sua é afetada.
 * - include_me: false = compra para outra pessoa — você pagou, sua parte é zero e o valor fica "a receber".
 */
class SplitData extends Data
{
    public function __construct(
        #[In(['equal', 'custom'])]
        public string $mode = 'equal',

        /** @var array<int, SplitParticipantData> */
        #[DataCollectionOf(SplitParticipantData::class)]
        public array $participants = [],

        public ?string $paid_by_contact_id = null,

        public bool $include_me = true,
    ) {}

    /**
     * @return array<string, array<int, mixed>>
     */
    public static function rules(): array
    {
        return [
            'participants' => ['required', 'array', 'min:1'],
            'paid_by_contact_id' => ['nullable', 'uuid', Rule::exists('contacts', 'id')->where('user_id', Auth::id())],
        ];
    }

    /**
     * IDs dos contatos participantes (sem você).
     *
     * @return list<string>
     */
    public function contactIds(): array
    {
        return array_values(array_filter(array_map(
            fn (SplitParticipantData $p) => $p->contact_id,
            $this->participants,
        )));
    }
}
