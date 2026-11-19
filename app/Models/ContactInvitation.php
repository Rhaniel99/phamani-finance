<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Carbon;

/**
 * Convite para vincular um contato a um usuário do Phamani (pelo e-mail do Google).
 *
 * @property string $id
 * @property string $user_id
 * @property string $contact_id
 * @property string $email
 * @property string $status pending|accepted|declined|cancelled
 * @property string|null $recipient_user_id
 * @property Carbon|null $responded_at
 */
class ContactInvitation extends BaseModel
{
    protected $fillable = [
        'user_id',
        'contact_id',
        'email',
        'status',
        'recipient_user_id',
        'responded_at',
    ];

    protected $casts = [
        'responded_at' => 'datetime',
    ];

    /** @return BelongsTo<User, $this> */
    public function inviter(): BelongsTo
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    /** @return BelongsTo<Contact, $this> */
    public function contact(): BelongsTo
    {
        return $this->belongsTo(Contact::class);
    }
}
