<?php

namespace App\Models;

/**
 * Memória de loja: descrição do extrato → nome, categoria e tags.
 *
 * @property string $id
 * @property string $user_id
 * @property string $key
 * @property string $name
 * @property string|null $category_id
 * @property list<string>|null $tags
 */
class MerchantRule extends BaseModel
{
    protected $fillable = ['user_id', 'key', 'name', 'category_id', 'tags'];

    protected $casts = ['tags' => 'array'];
}
