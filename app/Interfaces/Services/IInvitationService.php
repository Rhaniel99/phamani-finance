<?php

namespace App\Interfaces\Services;

use App\Models\Contact;
use App\Models\ContactInvitation;
use App\Models\User;
use Illuminate\Support\Collection;

interface IInvitationService
{
    /**
     * Convida, pelo e-mail do Google, a pessoa por trás de um contato.
     * Funciona mesmo que ela ainda não use o Phamani: o convite aparece quando ela entrar.
     */
    public function invite(Contact $contact, string $email): ContactInvitation;

    /**
     * Convites pendentes para o e-mail do usuário.
     *
     * @return Collection<int, ContactInvitation>
     */
    public function pendingFor(User $user): Collection;

    /**
     * Aceita: vincula o contato de quem convidou a este usuário e cria/vincula, no sistema dele,
     * um contato para quem convidou.
     */
    public function accept(ContactInvitation $invitation, User $user): void;

    public function decline(ContactInvitation $invitation, User $user): void;

    /**
     * Desfaz o vínculo dos dois lados. Cópias já aceitas continuam como estão.
     */
    public function unlink(Contact $contact): void;
}
