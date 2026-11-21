<?php

namespace App\Http\Controllers;

use App\DTOs\Contact\StoreContactData;
use App\DTOs\Contact\UpdateContactData;
use App\Interfaces\Services\IContactService;
use App\Models\Contact;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;
use Inertia\Inertia;

class ContactController extends Controller
{
    public function __construct(
        protected IContactService $service,
    ) {}

    public function store(Request $request, StoreContactData $data): RedirectResponse
    {
        $contact = $this->service->create((string) $request->user()?->getAuthIdentifier(), $data);

        Inertia::flash('toast', ['type' => 'success', 'message' => "{$contact->name} adicionado aos contatos."]);

        return back();
    }

    public function update(Request $request, Contact $contact, UpdateContactData $data): RedirectResponse
    {
        abort_unless($contact->user_id === (string) $request->user()?->getAuthIdentifier(), 404);

        $this->service->rename($contact, $data);

        Inertia::flash('toast', ['type' => 'success', 'message' => $contact->wasChanged('track_debts') && ! $contact->wasChanged('name')
            ? ($contact->track_debts ? "{$contact->name} entra no acerto." : "{$contact->name} não é mais cobrado no acerto.")
            : 'Contato atualizado.']);

        return back();
    }

    public function destroy(Request $request, Contact $contact): RedirectResponse
    {
        abort_unless($contact->user_id === (string) $request->user()?->getAuthIdentifier(), 404);

        try {
            $this->service->delete($contact);
        } catch (ValidationException $e) {
            Inertia::flash('toast', ['type' => 'error', 'message' => $e->getMessage()]);

            return back();
        }

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Contato excluído.']);

        return back();
    }
}
